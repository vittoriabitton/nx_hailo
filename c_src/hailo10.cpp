// NIF implementation for Hailo-10 / Hailo-15 using HailoRT v5 (master branch)
// VDevice::create_infer_model() + InferModel + ConfiguredInferModel API.

#include "hailo/hailort.hpp"
#include <fine.hpp>
#include <map>
#include <memory>
#include <string>
#include <vector>
#include <chrono>

using namespace hailort;

// Resource: VDevice (for create_vdevice / configure_network_group flow)
struct VDeviceResource {
  std::shared_ptr<VDevice> vdevice;
};

// Resource: holds InferModel + ConfiguredInferModel; used as both "network group" and "pipeline"
struct InferModelResource {
  std::shared_ptr<VDevice> vdevice;
  std::shared_ptr<InferModel> infer_model;
  // HailoRT v5: configure() returns ConfiguredInferModel by value (not shared_ptr)
  std::unique_ptr<ConfiguredInferModel> configured_model;

  // Called by fine right before ~InferModelResource(). Draining the model here
  // means in-flight transfers are cancelled while the InferModel and VDevice
  // this resource owns are still alive.
  void destructor(ErlNifEnv *env) {
    (void)env;
    if (configured_model) {
      (void)configured_model->shutdown();
    }
  }
};

FINE_RESOURCE(VDeviceResource);
FINE_RESOURCE(InferModelResource);

static fine::Term fine_error_string(ErlNifEnv *env, const std::string &message) {
  std::tuple<fine::Atom, std::string> tagged_result(fine::Atom("error"), message);
  return fine::encode(env, tagged_result);
}

template <typename T>
static fine::Term fine_ok(ErlNifEnv *env, T value) {
  std::tuple<fine::Atom, T> tagged_result(fine::Atom("ok"), value);
  return fine::encode(env, tagged_result);
}

static fine::Atom format_type_to_atom(hailo_format_type_t type) {
  switch (type) {
  case HAILO_FORMAT_TYPE_AUTO: return fine::Atom("auto");
  case HAILO_FORMAT_TYPE_UINT8: return fine::Atom("uint8");
  case HAILO_FORMAT_TYPE_UINT16: return fine::Atom("uint16");
  case HAILO_FORMAT_TYPE_FLOAT32: return fine::Atom("float32");
  default: return fine::Atom("unknown_type");
  }
}

static fine::Atom format_order_to_atom(hailo_format_order_t order) {
  switch (order) {
  case HAILO_FORMAT_ORDER_AUTO: return fine::Atom("auto");
  case HAILO_FORMAT_ORDER_NHWC: return fine::Atom("nhwc");
  case HAILO_FORMAT_ORDER_NHCW: return fine::Atom("nhcw");
  case HAILO_FORMAT_ORDER_NCHW: return fine::Atom("nchw");
  case HAILO_FORMAT_ORDER_FCR: return fine::Atom("fcr");
  case HAILO_FORMAT_ORDER_HAILO_NMS: return fine::Atom("hailo_nms");
  case HAILO_FORMAT_ORDER_HAILO_NMS_WITH_BYTE_MASK: return fine::Atom("hailo_nms_with_byte_mask");
  case HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS: return fine::Atom("hailo_nms_by_class");
  case HAILO_FORMAT_ORDER_HAILO_NMS_BY_SCORE: return fine::Atom("hailo_nms_by_score");
  case HAILO_FORMAT_ORDER_HAILO_NMS_ON_CHIP: return fine::Atom("hailo_nms_on_chip");
  default: return fine::Atom("unknown_order");
  }
}

static fine::Atom format_flags_to_atom(hailo_format_flags_t flags) {
  if (flags == HAILO_FORMAT_FLAGS_NONE) return fine::Atom("none");
  if (flags == HAILO_FORMAT_FLAGS_TRANSPOSED) return fine::Atom("transposed");
  return fine::Atom("unknown_flags");
}

// Build vstream info map from InferModel::InferStream (same shape as hailo8 for Elixir compatibility)
static ERL_NIF_TERM build_vstream_info_map_from_stream(
    ErlNifEnv *env,
    const InferModel::InferStream &stream,
    bool is_output) {
  ERL_NIF_TERM map_term = enif_make_new_map(env);
  const std::string name = stream.name();
  hailo_format_t fmt = stream.format();
  hailo_3d_image_shape_t shape = stream.shape();
  uint32_t calculated_frame_size = static_cast<uint32_t>(stream.get_frame_size());

  enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("name")),
                    fine::encode(env, name), &map_term);
  enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("network_name")),
                    fine::encode(env, name), &map_term);
  ERL_NIF_TERM direction_atom = is_output ? fine::encode(env, fine::Atom("d2h"))
                                           : fine::encode(env, fine::Atom("h2d"));
  enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("direction")),
                    direction_atom, &map_term);

  ERL_NIF_TERM format_map_erl = enif_make_new_map(env);
  hailo_format_order_t actual_order = fmt.order;
  enif_make_map_put(env, format_map_erl, fine::encode(env, fine::Atom("type")),
                    fine::encode(env, format_type_to_atom(fmt.type)), &format_map_erl);
  enif_make_map_put(env, format_map_erl, fine::encode(env, fine::Atom("order")),
                    fine::encode(env, format_order_to_atom(actual_order)), &format_map_erl);
  enif_make_map_put(env, format_map_erl, fine::encode(env, fine::Atom("flags")),
                    fine::encode(env, format_flags_to_atom(fmt.flags)), &format_map_erl);
  enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("format")),
                    format_map_erl, &map_term);

  bool is_nms = stream.is_nms();
  if (is_nms) {
    auto nms_exp = stream.get_nms_shape();
    if (nms_exp) {
      const hailo_nms_shape_t &nms = nms_exp.value();
      ERL_NIF_TERM nms_shape_map_erl = enif_make_new_map(env);
      enif_make_map_put(env, nms_shape_map_erl,
                        fine::encode(env, fine::Atom("number_of_classes")),
                        fine::encode(env, static_cast<uint64_t>(nms.number_of_classes)), &nms_shape_map_erl);
      enif_make_map_put(env, nms_shape_map_erl,
                        fine::encode(env, fine::Atom("max_bboxes_per_class")),
                        fine::encode(env, static_cast<uint64_t>(nms.max_bboxes_per_class)), &nms_shape_map_erl);
      enif_make_map_put(env, nms_shape_map_erl,
                        fine::encode(env, fine::Atom("max_bboxes_total")),
                        fine::encode(env, static_cast<uint64_t>(nms.max_bboxes_total)), &nms_shape_map_erl);
      enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("nms_shape")),
                        nms_shape_map_erl, &map_term);
    }
    enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("shape")),
                      fine::encode(env, fine::Atom("nil")), &map_term);
  } else {
    ERL_NIF_TERM shape_map_erl = enif_make_new_map(env);
    enif_make_map_put(env, shape_map_erl, fine::encode(env, fine::Atom("height")),
                      fine::encode(env, static_cast<uint64_t>(shape.height)), &shape_map_erl);
    enif_make_map_put(env, shape_map_erl, fine::encode(env, fine::Atom("width")),
                      fine::encode(env, static_cast<uint64_t>(shape.width)), &shape_map_erl);
    enif_make_map_put(env, shape_map_erl, fine::encode(env, fine::Atom("features")),
                      fine::encode(env, static_cast<uint64_t>(shape.features)), &shape_map_erl);
    enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("shape")),
                      shape_map_erl, &map_term);
    enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("nms_shape")),
                      fine::encode(env, fine::Atom("nil")), &map_term);
  }

  enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("frame_size")),
                    fine::encode(env, static_cast<uint64_t>(calculated_frame_size)),
                    &map_term);

  double qp_zp = 0.0, qp_scale = 0.0;
  std::vector<hailo_quant_info_t> quant_infos = stream.get_quant_infos();
  if (!quant_infos.empty()) {
    qp_zp = static_cast<double>(quant_infos[0].qp_zp);
    qp_scale = static_cast<double>(quant_infos[0].qp_scale);
  }
  ERL_NIF_TERM quant_info_map_erl = enif_make_new_map(env);
  enif_make_map_put(env, quant_info_map_erl, fine::encode(env, fine::Atom("qp_zp")),
                    fine::encode(env, qp_zp), &quant_info_map_erl);
  enif_make_map_put(env, quant_info_map_erl, fine::encode(env, fine::Atom("qp_scale")),
                    fine::encode(env, qp_scale), &quant_info_map_erl);
  if (qp_zp != 0.0 || qp_scale != 0.0) {
    enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("quant_info")),
                      quant_info_map_erl, &map_term);
  } else {
    enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("quant_info")),
                      fine::encode(env, fine::Atom("nil")), &map_term);
  }
  return map_term;
}

fine::Term create_vdevice(ErlNifEnv *env) {
  auto vdevice_exp = VDevice::create_shared();
  if (!vdevice_exp) {
    return fine_error_string(env, "Failed to create VDevice: " +
                                  std::to_string(vdevice_exp.status()));
  }
  auto resource = fine::make_resource<VDeviceResource>();
  resource->vdevice = std::move(vdevice_exp.value());
  return fine_ok(env, resource);
}

fine::Term configure_network_group(ErlNifEnv *env,
                                   fine::Term vdevice_resource_term,
                                   fine::Term hef_path_term) {
  fine::ResourcePtr<VDeviceResource> vdevice_res;
  try {
    vdevice_res = fine::decode<fine::ResourcePtr<VDeviceResource>>(env, vdevice_resource_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid VDevice resource");
  }
  std::string hef_path;
  try {
    hef_path = fine::decode<std::string>(env, hef_path_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid HEF file path");
  }
  auto infer_model_exp = vdevice_res->vdevice->create_infer_model(hef_path);
  if (!infer_model_exp) {
    return fine_error_string(env, "Failed to create InferModel: " +
                                  std::to_string(infer_model_exp.status()));
  }
  std::shared_ptr<InferModel> infer_model = infer_model_exp.value();
  auto configured_exp = infer_model->configure();
  if (!configured_exp) {
    return fine_error_string(env, "Failed to configure InferModel: " +
                                  std::to_string(configured_exp.status()));
  }
  auto configured_model =
      std::make_unique<ConfiguredInferModel>(std::move(configured_exp.value()));
  hailo_status act_status = configured_model->activate();
  if (act_status != HAILO_SUCCESS && act_status != HAILO_INVALID_OPERATION) {
    return fine_error_string(env, "Failed to activate model: " +
                                  std::to_string(act_status));
  }
  auto resource = fine::make_resource<InferModelResource>();
  resource->vdevice = vdevice_res->vdevice;
  resource->infer_model = std::move(infer_model);
  resource->configured_model = std::move(configured_model);
  return fine_ok(env, resource);
}

fine::Term create_pipeline(ErlNifEnv *env, fine::Term network_group_term) {
  fine::ResourcePtr<InferModelResource> res;
  try {
    res = fine::decode<fine::ResourcePtr<InferModelResource>>(env, network_group_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid network group resource");
  }
  return fine_ok(env, res);
}

fine::Term get_input_vstream_infos_from_ng(ErlNifEnv *env,
                                           fine::Term network_group_term) {
  fine::ResourcePtr<InferModelResource> res;
  try {
    res = fine::decode<fine::ResourcePtr<InferModelResource>>(env, network_group_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid network group resource");
  }
  const auto &inputs = res->infer_model->inputs();
  std::vector<ERL_NIF_TERM> map_terms_vector;
  for (const auto &stream : inputs) {
    map_terms_vector.push_back(build_vstream_info_map_from_stream(env, stream, false));
  }
  ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(
      env, map_terms_vector.data(), map_terms_vector.size());
  return fine_ok(env, fine::Term(list_of_maps_term));
}

fine::Term get_output_vstream_infos_from_ng(ErlNifEnv *env,
                                            fine::Term network_group_term) {
  fine::ResourcePtr<InferModelResource> res;
  try {
    res = fine::decode<fine::ResourcePtr<InferModelResource>>(env, network_group_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid network group resource");
  }
  const auto &outputs = res->infer_model->outputs();
  std::vector<ERL_NIF_TERM> map_terms_vector;
  for (const auto &stream : outputs) {
    map_terms_vector.push_back(build_vstream_info_map_from_stream(env, stream, true));
  }
  ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(
      env, map_terms_vector.data(), map_terms_vector.size());
  return fine_ok(env, fine::Term(list_of_maps_term));
}

fine::Term get_input_vstream_infos_from_pipeline(ErlNifEnv *env,
                                                 fine::Term pipeline_term) {
  return get_input_vstream_infos_from_ng(env, pipeline_term);
}

fine::Term get_output_vstream_infos_from_pipeline(ErlNifEnv *env,
                                                 fine::Term pipeline_term) {
  return get_output_vstream_infos_from_ng(env, pipeline_term);
}

fine::Term infer(ErlNifEnv *env, fine::Term pipeline_term,
                fine::Term input_data_term) {
  fine::ResourcePtr<InferModelResource> res;
  try {
    res = fine::decode<fine::ResourcePtr<InferModelResource>>(env, pipeline_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid pipeline resource");
  }
  std::map<std::string, std::string> input_map;
  try {
    input_map = fine::decode<std::map<std::string, std::string>>(env, input_data_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Input data must be a map");
  }

  const auto &input_names = res->infer_model->get_input_names();
  const auto &output_names = res->infer_model->get_output_names();

  std::map<std::string, MemoryView> buffers;
  for (const std::string &name : input_names) {
    auto it = input_map.find(name);
    if (it == input_map.end()) {
      return fine_error_string(env, "Missing input data for: " + name);
    }
    const std::string &binary = it->second;
    auto input_stream_exp = res->infer_model->input(name);
    if (!input_stream_exp) {
      return fine_error_string(env, "Failed to get input stream: " + name);
    }
    size_t expected_size = input_stream_exp->get_frame_size();
    if (binary.size() != expected_size) {
      return fine_error_string(env, "Invalid input size for " + name +
                                    ". Expected: " + std::to_string(expected_size) +
                                    ", Got: " + std::to_string(binary.size()));
    }
    buffers[name] = MemoryView(const_cast<void *>(static_cast<const void *>(binary.data())), binary.size());
  }

  std::map<std::string, std::vector<uint8_t>> output_buffers;
  for (const std::string &name : output_names) {
    auto output_stream_exp = res->infer_model->output(name);
    if (!output_stream_exp) {
      return fine_error_string(env, "Failed to get output stream: " + name);
    }
    size_t frame_size = output_stream_exp->get_frame_size();
    output_buffers[name].resize(frame_size);
    buffers[name] = MemoryView(output_buffers[name].data(), frame_size);
  }

  auto bindings_exp = res->configured_model->create_bindings(buffers);
  if (!bindings_exp) {
    return fine_error_string(env, "Failed to create bindings: " +
                                  std::to_string(bindings_exp.status()));
  }

  constexpr auto timeout = std::chrono::milliseconds(30000);
  hailo_status status =
      res->configured_model->run(bindings_exp.value(), timeout);
  if (status != HAILO_SUCCESS) {
    return fine_error_string(env, "Inference failed: " + std::to_string(status));
  }

  std::map<std::string, std::string> output_map;
  for (const std::string &name : output_names) {
    const auto &buf = output_buffers[name];
    output_map[name] = std::string(reinterpret_cast<const char *>(buf.data()), buf.size());
  }
  return fine_ok(env, output_map);
}

// Configures a network group with scheduling options bundled in an opts map.
// Options (all optional):
//   scheduler_algorithm: :round_robin | :none   (VDevice-level; set via create_vdevice/1)
//   scheduler_timeout_ms: non-negative integer  (applied post-configure on ConfiguredInferModel)
//   scheduler_threshold: non-negative integer   (applied post-configure on ConfiguredInferModel)
//
// Note on HailoRT 5.x API: scheduler_timeout/threshold are set on ConfiguredInferModel
// after configure(). scheduling_algorithm is set at VDevice level.
fine::Term configure_network_group_opts(ErlNifEnv *env,
                                        fine::ResourcePtr<VDeviceResource> vdevice_res,
                                        std::string hef_path,
                                        fine::Term opts_term) {
  auto infer_model_exp = vdevice_res->vdevice->create_infer_model(hef_path);
  if (!infer_model_exp) {
    return fine_error_string(env, "Failed to create InferModel: " +
                                  std::to_string(infer_model_exp.status()));
  }
  std::shared_ptr<InferModel> infer_model = infer_model_exp.value();

  auto configured_exp = infer_model->configure();
  if (!configured_exp) {
    return fine_error_string(env, "Failed to configure InferModel: " +
                                  std::to_string(configured_exp.status()));
  }
  auto configured_model =
      std::make_unique<ConfiguredInferModel>(std::move(configured_exp.value()));

  ERL_NIF_TERM val;

  // Apply scheduler_timeout_ms post-configure
  if (enif_get_map_value(env, opts_term, fine::encode(env, fine::Atom("scheduler_timeout_ms")), &val)) {
    uint64_t timeout_ms = fine::decode<uint64_t>(env, fine::Term(val));
    hailo_status s = configured_model->set_scheduler_timeout(std::chrono::milliseconds(timeout_ms));
    if (s != HAILO_SUCCESS)
      return fine_error_string(env, "Failed to set scheduler timeout: " + std::to_string(s));
  }

  // Apply scheduler_threshold post-configure
  if (enif_get_map_value(env, opts_term, fine::encode(env, fine::Atom("scheduler_threshold")), &val)) {
    uint64_t threshold = fine::decode<uint64_t>(env, fine::Term(val));
    hailo_status s = configured_model->set_scheduler_threshold(static_cast<uint32_t>(threshold));
    if (s != HAILO_SUCCESS)
      return fine_error_string(env, "Failed to set scheduler threshold: " + std::to_string(s));
  }

  hailo_status act_status = configured_model->activate();
  if (act_status != HAILO_SUCCESS && act_status != HAILO_INVALID_OPERATION) {
    return fine_error_string(env, "Failed to activate model: " + std::to_string(act_status));
  }

  auto resource = fine::make_resource<InferModelResource>();
  resource->vdevice = vdevice_res->vdevice;
  resource->infer_model = std::move(infer_model);
  resource->configured_model = std::move(configured_model);
  return fine_ok(env, resource);
}

// Arity-1 create_vdevice: scheduling_algorithm is a VDevice-level setting on
// hailo10 too; use hailo_init_vdevice_params for safe default initialization.
fine::Term create_vdevice_opts(ErlNifEnv *env, fine::Term opts_term) {
  ERL_NIF_TERM val;
  if (!enif_get_map_value(env, opts_term, fine::encode(env, fine::Atom("scheduling_algorithm")), &val)) {
    return create_vdevice(env);
  }

  fine::Atom alg = fine::decode<fine::Atom>(env, fine::Term(val));

  hailo_vdevice_params_t params;
  hailo_status init_s = hailo_init_vdevice_params(&params);
  if (init_s != HAILO_SUCCESS)
    return fine_error_string(env, "Failed to init vdevice params: " + std::to_string(init_s));

  if (alg == "round_robin") {
    params.scheduling_algorithm = HAILO_SCHEDULING_ALGORITHM_ROUND_ROBIN;
  } else if (alg == "none") {
    params.scheduling_algorithm = HAILO_SCHEDULING_ALGORITHM_NONE;
  } else {
    return fine_error_string(env, "Unknown scheduling_algorithm (expected :round_robin or :none)");
  }

  auto vdevice_exp = VDevice::create_shared(params);
  if (!vdevice_exp) {
    return fine_error_string(env, "Failed to create VDevice: " + std::to_string(vdevice_exp.status()));
  }
  auto resource = fine::make_resource<VDeviceResource>();
  resource->vdevice = std::move(vdevice_exp.value());
  return fine_ok(env, resource);
}

// set_scheduler_timeout and set_scheduler_threshold are not applicable as
// standalone NIFs for hailo10 — pass opts to configure_network_group/3 instead.
fine::Term set_scheduler_timeout(ErlNifEnv *env, fine::Term /*ng_ref*/,
                                 fine::Term /*timeout_ms*/) {
  return fine_error_string(env, "set_scheduler_timeout is not applicable for hailo10; "
                                "pass :scheduler_timeout_ms in configure_network_group/3 opts instead");
}

fine::Term set_scheduler_threshold(ErlNifEnv *env, fine::Term /*ng_ref*/,
                                   fine::Term /*threshold*/) {
  return fine_error_string(env, "set_scheduler_threshold is not applicable for hailo10; "
                                "pass :scheduler_threshold in configure_network_group/3 opts instead");
}

fine::Term hailo_version(ErlNifEnv *env) {
  return fine::encode(env, fine::Atom("hailo10"));
}

// Register NIF functions
FINE_NIF(hailo_version, 0);
FINE_NIF(create_pipeline, 1);
FINE_NIF(get_output_vstream_infos_from_pipeline, 1);
// infer: ERL_NIF_DIRTY_JOB_IO_BOUND (flags=2)
FINE_NIF(infer, 2);
FINE_NIF(get_input_vstream_infos_from_ng, 1);
FINE_NIF(get_output_vstream_infos_from_ng, 1);
FINE_NIF(get_input_vstream_infos_from_pipeline, 1);
FINE_NIF(set_scheduler_timeout, 0);
FINE_NIF(set_scheduler_threshold, 0);

// create_vdevice/1 and configure_network_group/3 use custom C++ names so
// they are registered manually below (api.ex always delegates through these).
static ERL_NIF_TERM configure_network_group_opts_nif(ErlNifEnv *env, int argc,
                                                      const ERL_NIF_TERM argv[]) {
  return fine::nif(env, argc, argv, configure_network_group_opts);
}
static auto __nif_reg_cng3 = fine::Registration::register_nif(
    {"configure_network_group", fine::nif_arity(configure_network_group_opts),
     configure_network_group_opts_nif, ERL_NIF_DIRTY_JOB_IO_BOUND});

static ERL_NIF_TERM create_vdevice_opts_nif(ErlNifEnv *env, int argc,
                                             const ERL_NIF_TERM argv[]) {
  return fine::nif(env, argc, argv, create_vdevice_opts);
}
static auto __nif_reg_vd1 = fine::Registration::register_nif(
    {"create_vdevice", fine::nif_arity(create_vdevice_opts), create_vdevice_opts_nif, 0});

FINE_INIT("Elixir.NxHailo.NIF");
