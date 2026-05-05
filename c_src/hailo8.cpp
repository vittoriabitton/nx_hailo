// NIF implementation for Hailo-8 / Hailo-8R / Hailo-8L using HailoRT hailo8 branch
// (VDevice / ConfigureParams / InferVStreams API).

#include "hailo/hailort.hpp"
#include <fine.hpp>
#include <chrono>
#include <map>
#include <memory>
#include <string>
#include <vector>

// Resource type for VDevice
struct VDeviceResource {
  std::shared_ptr<hailort::VDevice> vdevice;
};

// Resource type for ConfiguredNetworkGroup
struct NetworkGroupResource {
  std::shared_ptr<hailort::ConfiguredNetworkGroup> network_group;
  std::shared_ptr<hailort::VDevice>
      vdevice; // Keep a reference to vdevice to ensure it lives as long as the
               // network group
};

// Resource type for InferVStreams
struct InferPipelineResource {
  std::shared_ptr<hailort::InferVStreams> pipeline;
  std::shared_ptr<hailort::ConfiguredNetworkGroup>
      network_group; // Keep a reference to network_group
};

// Destructor for VDeviceResource
void vdevice_resource_dtor(ErlNifEnv *env, void *obj) {
  auto *res = static_cast<VDeviceResource *>(obj);
  res->vdevice.reset();
  delete res;
}

// Destructor for NetworkGroupResource
void network_group_resource_dtor(ErlNifEnv *env, void *obj) {
  auto *res = static_cast<NetworkGroupResource *>(obj);
  res->network_group.reset();
  res->vdevice.reset();
  delete res;
}

// Destructor for InferPipelineResource
void infer_pipeline_resource_dtor(ErlNifEnv *env, void *obj) {
  auto *res = static_cast<InferPipelineResource *>(obj);
  res->pipeline.reset();
  res->network_group.reset();
  delete res;
}

// Define resource types using FINE macros
FINE_RESOURCE(VDeviceResource);
FINE_RESOURCE(NetworkGroupResource);
FINE_RESOURCE(InferPipelineResource);

fine::Term fine_error_string(ErlNifEnv *env, const std::string &message) {
  std::tuple<fine::Atom, std::string> tagged_result(fine::Atom("error"),
                                                    message);
  return fine::encode(env, tagged_result);
}

template <typename T> fine::Term fine_ok(ErlNifEnv *env, T value) {
  std::tuple<fine::Atom, T> tagged_result(fine::Atom("ok"), value);
  return fine::encode(env, tagged_result);
}

// Helper function to convert hailo_format_type_t to Elixir atom
fine::Atom format_type_to_atom(hailo_format_type_t type) {
  switch (type) {
  case HAILO_FORMAT_TYPE_AUTO:
    return fine::Atom("auto");
  case HAILO_FORMAT_TYPE_UINT8:
    return fine::Atom("uint8");
  case HAILO_FORMAT_TYPE_UINT16:
    return fine::Atom("uint16");
  case HAILO_FORMAT_TYPE_FLOAT32:
    return fine::Atom("float32");
  default:
    return fine::Atom("unknown_type");
  }
}

// Helper function to convert hailo_format_order_t to Elixir atom
fine::Atom format_order_to_atom(hailo_format_order_t order) {
  switch (order) {
  case HAILO_FORMAT_ORDER_AUTO:
    return fine::Atom("auto");
  case HAILO_FORMAT_ORDER_NHWC:
    return fine::Atom("nhwc");
  case HAILO_FORMAT_ORDER_NHCW:
    return fine::Atom("nhcw");
  case HAILO_FORMAT_ORDER_NCHW:
    return fine::Atom("nchw");
  case HAILO_FORMAT_ORDER_FCR:
    return fine::Atom("fcr");
  case HAILO_FORMAT_ORDER_HAILO_NMS:
    return fine::Atom("hailo_nms");
  case HAILO_FORMAT_ORDER_HAILO_NMS_WITH_BYTE_MASK:
    return fine::Atom("hailo_nms_with_byte_mask");
  case HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS:
    return fine::Atom("hailo_nms_by_class");
  case HAILO_FORMAT_ORDER_HAILO_NMS_BY_SCORE:
    return fine::Atom("hailo_nms_by_score");
  case HAILO_FORMAT_ORDER_HAILO_NMS_ON_CHIP:
    return fine::Atom("hailo_nms_on_chip");
  default:
    return fine::Atom("unknown_order");
  }
}

// Helper function to convert hailo_format_flags_t to Elixir atom
fine::Atom format_flags_to_atom(hailo_format_flags_t flags) {
  if (flags == HAILO_FORMAT_FLAGS_NONE)
    return fine::Atom("none");
  if (flags == HAILO_FORMAT_FLAGS_TRANSPOSED)
    return fine::Atom("transposed");
  return fine::Atom(
      "unknown_flags"); // Default if no specific known flag matches
}

// NIF function to create a VDevice
fine::Term create_vdevice(ErlNifEnv *env) {
  auto vdevice_expected = hailort::VDevice::create();
  if (!vdevice_expected) {
    return fine_error_string(env,
                             "Failed to create virtual device: " +
                                 std::to_string(vdevice_expected.status()));
  }
  auto vdevice = std::move(vdevice_expected.value());

  auto resource = fine::make_resource<VDeviceResource>();
  resource->vdevice = std::move(vdevice);
  return fine_ok(env, resource);
}

// NIF function to configure a network group using an existing VDevice
fine::Term configure_network_group(ErlNifEnv *env,
                                   fine::Term vdevice_resource_term,
                                   fine::Term hef_path_term) {
  fine::ResourcePtr<VDeviceResource> vdevice_res;
  try {
    vdevice_res = fine::decode<fine::ResourcePtr<VDeviceResource>>(
        env, vdevice_resource_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid VDevice resource");
  }

  std::string hef_path;
  try {
    hef_path = fine::decode<std::string>(env, hef_path_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid HEF file path");
  }

  auto hef = hailort::Hef::create(hef_path);
  if (!hef) {
    return fine_error_string(env, "Failed to load HEF file: " +
                                      std::to_string(hef.status()));
  }

  auto configure_params =
      vdevice_res->vdevice->create_configure_params(hef.value());
  if (!configure_params) {
    return fine_error_string(env,
                             "Failed to create configure params: " +
                                 std::to_string(configure_params.status()));
  }

  auto network_groups =
      vdevice_res->vdevice->configure(hef.value(), configure_params.value());
  if (!network_groups) {
    return fine_error_string(env, "Failed to configure network groups: " +
                                      std::to_string(network_groups.status()));
  }

  if (network_groups->size() != 1) {
    return fine_error_string(env, "Invalid number of network groups: " +
                                      std::to_string(network_groups->size()));
  }

  auto resource = fine::make_resource<NetworkGroupResource>();
  resource->network_group = std::move(network_groups->at(0));
  resource->vdevice = vdevice_res->vdevice;
  return fine_ok(env, resource);
}

// NIF function to create an inference pipeline from a network group
fine::Term create_pipeline(ErlNifEnv *env, fine::Term network_group_term) {
  fine::ResourcePtr<NetworkGroupResource> ng_res;
  try {
    ng_res = fine::decode<fine::ResourcePtr<NetworkGroupResource>>(
        env, network_group_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid network group resource");
  }

  auto input_params = ng_res->network_group->make_input_vstream_params(
      {}, HAILO_FORMAT_TYPE_AUTO, HAILO_DEFAULT_VSTREAM_TIMEOUT_MS,
      HAILO_DEFAULT_VSTREAM_QUEUE_SIZE);
  if (!input_params) {
    return fine_error_string(env, "Failed to create input vstream params: " +
                                      std::to_string(input_params.status()));
  }

  auto output_params = ng_res->network_group->make_output_vstream_params(
      {}, HAILO_FORMAT_TYPE_AUTO, HAILO_DEFAULT_VSTREAM_TIMEOUT_MS,
      HAILO_DEFAULT_VSTREAM_QUEUE_SIZE);
  if (!output_params) {
    return fine_error_string(env, "Failed to create output vstream params: " +
                                      std::to_string(output_params.status()));
  }

  auto pipeline = hailort::InferVStreams::create(
      *ng_res->network_group, input_params.value(), output_params.value());
  if (!pipeline) {
    return fine_error_string(env, "Failed to create inference pipeline: " +
                                      std::to_string(pipeline.status()));
  }

  auto resource = fine::make_resource<InferPipelineResource>();
  resource->pipeline =
      std::make_shared<hailort::InferVStreams>(std::move(pipeline.value()));
  resource->network_group = ng_res->network_group;
  return fine_ok(env, resource);
}

ERL_NIF_TERM
build_detailed_vstream_info_map(ErlNifEnv *env,
                                const hailo_vstream_info_t &vstream_info) {
  ERL_NIF_TERM map_term = enif_make_new_map(env);
  uint32_t calculated_frame_size = 0;

  enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("name")),
                    fine::encode(env, std::string(vstream_info.name)),
                    &map_term);
  enif_make_map_put(
      env, map_term, fine::encode(env, fine::Atom("network_name")),
      fine::encode(env, std::string(vstream_info.network_name)), &map_term);
  ERL_NIF_TERM direction_atom_term =
      (vstream_info.direction == HAILO_D2H_STREAM)
          ? fine::encode(env, fine::Atom("d2h"))
          : fine::encode(env, fine::Atom("h2d"));
  enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("direction")),
                    direction_atom_term, &map_term);

  ERL_NIF_TERM format_map_erl = enif_make_new_map(env);
  hailo_format_order_t actual_format_order = vstream_info.format.order;
  enif_make_map_put(
      env, format_map_erl, fine::encode(env, fine::Atom("type")),
      fine::encode(env, format_type_to_atom(vstream_info.format.type)),
      &format_map_erl);
  enif_make_map_put(
      env, format_map_erl, fine::encode(env, fine::Atom("order")),
      fine::encode(env, format_order_to_atom(actual_format_order)),
      &format_map_erl);
  enif_make_map_put(
      env, format_map_erl, fine::encode(env, fine::Atom("flags")),
      fine::encode(env, format_flags_to_atom(vstream_info.format.flags)),
      &format_map_erl);
  enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("format")),
                    format_map_erl, &map_term);

  bool is_nms =
      (actual_format_order == HAILO_FORMAT_ORDER_HAILO_NMS ||
       actual_format_order == HAILO_FORMAT_ORDER_HAILO_NMS_WITH_BYTE_MASK ||
       actual_format_order == HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS ||
       actual_format_order == HAILO_FORMAT_ORDER_HAILO_NMS_BY_SCORE ||
       actual_format_order == HAILO_FORMAT_ORDER_HAILO_NMS_ON_CHIP);

  if (is_nms) {
    ERL_NIF_TERM nms_shape_map_erl = enif_make_new_map(env);
    enif_make_map_put(
        env, nms_shape_map_erl,
        fine::encode(env, fine::Atom("number_of_classes")),
        fine::encode(env, static_cast<uint64_t>(
                              vstream_info.nms_shape.number_of_classes)),
        &nms_shape_map_erl);
    enif_make_map_put(
        env, nms_shape_map_erl,
        fine::encode(env, fine::Atom("max_bboxes_per_class")),
        fine::encode(env, static_cast<uint64_t>(
                              vstream_info.nms_shape.max_bboxes_per_class)),
        &nms_shape_map_erl);
    enif_make_map_put(
        env, nms_shape_map_erl,
        fine::encode(env, fine::Atom("max_bboxes_total")),
        fine::encode(env, static_cast<uint64_t>(
                              vstream_info.nms_shape.max_bboxes_total)),
        &nms_shape_map_erl);
    enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("nms_shape")),
                      nms_shape_map_erl, &map_term);
    enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("shape")),
                      fine::encode(env, fine::Atom("nil")), &map_term);

    uint32_t num_detections_for_size_calc = 0;
    if (vstream_info.format.order == HAILO_FORMAT_ORDER_HAILO_NMS_BY_CLASS ||
        vstream_info.format.order == HAILO_FORMAT_ORDER_HAILO_NMS_ON_CHIP) {
      num_detections_for_size_calc =
          vstream_info.nms_shape.number_of_classes *
          vstream_info.nms_shape.max_bboxes_per_class;
    } else if (vstream_info.format.order ==
               HAILO_FORMAT_ORDER_HAILO_NMS_BY_SCORE) {
      num_detections_for_size_calc = vstream_info.nms_shape.max_bboxes_total;
    } else {
      num_detections_for_size_calc =
          vstream_info.nms_shape.number_of_classes *
          vstream_info.nms_shape.max_bboxes_per_class;
    }
    uint32_t elements_per_detection = 6;
    if (vstream_info.format.type == HAILO_FORMAT_TYPE_FLOAT32) {
      calculated_frame_size =
          num_detections_for_size_calc * elements_per_detection * sizeof(float);
    } else if (vstream_info.format.type == HAILO_FORMAT_TYPE_UINT8) {
      calculated_frame_size = num_detections_for_size_calc *
                              elements_per_detection * sizeof(uint8_t);
    } else {
      calculated_frame_size = 0;
    }
  } else {
    ERL_NIF_TERM shape_map_erl = enif_make_new_map(env);
    enif_make_map_put(
        env, shape_map_erl, fine::encode(env, fine::Atom("height")),
        fine::encode(env, static_cast<uint64_t>(vstream_info.shape.height)),
        &shape_map_erl);
    enif_make_map_put(
        env, shape_map_erl, fine::encode(env, fine::Atom("width")),
        fine::encode(env, static_cast<uint64_t>(vstream_info.shape.width)),
        &shape_map_erl);
    enif_make_map_put(
        env, shape_map_erl, fine::encode(env, fine::Atom("features")),
        fine::encode(env, static_cast<uint64_t>(vstream_info.shape.features)),
        &shape_map_erl);
    enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("shape")),
                      shape_map_erl, &map_term);
    enif_make_map_put(env, map_term, fine::encode(env, fine::Atom("nms_shape")),
                      fine::encode(env, fine::Atom("nil")), &map_term);
    calculated_frame_size = hailort::HailoRTCommon::get_frame_size(
        vstream_info.shape, vstream_info.format);
  }

  enif_make_map_put(
      env, map_term, fine::encode(env, fine::Atom("frame_size")),
      fine::encode(env, static_cast<uint64_t>(calculated_frame_size)),
      &map_term);

  ERL_NIF_TERM quant_info_map_erl = enif_make_new_map(env);
  enif_make_map_put(
      env, quant_info_map_erl, fine::encode(env, fine::Atom("qp_zp")),
      fine::encode(env, static_cast<double>(vstream_info.quant_info.qp_zp)),
      &quant_info_map_erl);
  enif_make_map_put(
      env, quant_info_map_erl, fine::encode(env, fine::Atom("qp_scale")),
      fine::encode(env, static_cast<double>(vstream_info.quant_info.qp_scale)),
      &quant_info_map_erl);
  if (vstream_info.quant_info.qp_zp != 0.0f ||
      vstream_info.quant_info.qp_scale != 0.0f) {
    enif_make_map_put(env, map_term,
                      fine::encode(env, fine::Atom("quant_info")),
                      quant_info_map_erl, &map_term);
  } else {
    enif_make_map_put(env, map_term,
                      fine::encode(env, fine::Atom("quant_info")),
                      fine::encode(env, fine::Atom("nil")), &map_term);
  }
  return map_term;
}

fine::Term get_input_vstream_infos_from_ng(ErlNifEnv *env,
                                           fine::Term network_group_term) {
  fine::ResourcePtr<NetworkGroupResource> ng_res;
  try {
    ng_res = fine::decode<fine::ResourcePtr<NetworkGroupResource>>(
        env, network_group_term);
  } catch (const std::exception &e) {
    return fine_error_string(
        env, "Invalid network group resource for getting input vstream infos");
  }
  auto vstream_infos_expected =
      ng_res->network_group->get_input_vstream_infos();
  if (!vstream_infos_expected) {
    return fine_error_string(
        env, "Failed to get input vstream infos from network group: " +
                 std::to_string(vstream_infos_expected.status()));
  }
  std::vector<ERL_NIF_TERM> map_terms_vector;
  for (const auto &info : vstream_infos_expected.value()) {
    map_terms_vector.push_back(build_detailed_vstream_info_map(env, info));
  }
  ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(
      env, map_terms_vector.data(), map_terms_vector.size());
  return fine_ok(env, fine::Term(list_of_maps_term));
}

fine::Term get_output_vstream_infos_from_ng(ErlNifEnv *env,
                                            fine::Term network_group_term) {
  fine::ResourcePtr<NetworkGroupResource> ng_res;
  try {
    ng_res = fine::decode<fine::ResourcePtr<NetworkGroupResource>>(
        env, network_group_term);
  } catch (const std::exception &e) {
    return fine_error_string(
        env, "Invalid network group resource for getting output vstream infos");
  }
  auto vstream_infos_expected =
      ng_res->network_group->get_output_vstream_infos();
  if (!vstream_infos_expected) {
    return fine_error_string(
        env, "Failed to get output vstream infos from network group: " +
                 std::to_string(vstream_infos_expected.status()));
  }
  std::vector<ERL_NIF_TERM> map_terms_vector;
  for (const auto &info : vstream_infos_expected.value()) {
    map_terms_vector.push_back(build_detailed_vstream_info_map(env, info));
  }
  ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(
      env, map_terms_vector.data(), map_terms_vector.size());
  return fine_ok(env, fine::Term(list_of_maps_term));
}

fine::Term get_input_vstream_infos_from_pipeline(ErlNifEnv *env,
                                                 fine::Term pipeline_term) {
  fine::ResourcePtr<InferPipelineResource> pipeline_res;
  try {
    pipeline_res = fine::decode<fine::ResourcePtr<InferPipelineResource>>(
        env, pipeline_term);
  } catch (const std::exception &e) {
    return fine_error_string(
        env, "Invalid pipeline resource for getting input vstream infos");
  }
  auto all_ng_input_infos_expected =
      pipeline_res->network_group->get_input_vstream_infos();
  if (!all_ng_input_infos_expected) {
    return fine_error_string(
        env,
        "Failed to get input vstream infos from network group for pipeline: " +
            std::to_string(all_ng_input_infos_expected.status()));
  }
  const auto &all_ng_input_infos = all_ng_input_infos_expected.value();
  auto active_pipeline_input_vstreams =
      pipeline_res->pipeline->get_input_vstreams();
  std::vector<ERL_NIF_TERM> map_terms_vector;
  for (const auto &active_vstream_ref : active_pipeline_input_vstreams) {
    std::string active_name = active_vstream_ref.get().name();
    bool found = false;
    for (const auto &info_t : all_ng_input_infos) {
      if (std::string(info_t.name) == active_name) {
        map_terms_vector.push_back(
            build_detailed_vstream_info_map(env, info_t));
        found = true;
        break;
      }
    }
    if (!found) {
      ERL_NIF_TERM error_map = enif_make_new_map(env);
      enif_make_map_put(
          env, error_map, fine::encode(env, fine::Atom("error")),
          fine::encode(env, "Info not found for active stream: " + active_name),
          &error_map);
      map_terms_vector.push_back(error_map);
    }
  }
  ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(
      env, map_terms_vector.data(), map_terms_vector.size());
  return fine_ok(env, fine::Term(list_of_maps_term));
}

fine::Term get_output_vstream_infos_from_pipeline(ErlNifEnv *env,
                                                  fine::Term pipeline_term) {
  fine::ResourcePtr<InferPipelineResource> pipeline_res;
  try {
    pipeline_res = fine::decode<fine::ResourcePtr<InferPipelineResource>>(
        env, pipeline_term);
  } catch (const std::exception &e) {
    return fine_error_string(
        env, "Invalid pipeline resource for getting output vstream infos");
  }
  auto all_ng_output_infos_expected =
      pipeline_res->network_group->get_output_vstream_infos();
  if (!all_ng_output_infos_expected) {
    return fine_error_string(
        env,
        "Failed to get output vstream infos from network group for pipeline: " +
            std::to_string(all_ng_output_infos_expected.status()));
  }
  const auto &all_ng_output_infos = all_ng_output_infos_expected.value();
  auto active_pipeline_output_vstreams =
      pipeline_res->pipeline->get_output_vstreams();
  std::vector<ERL_NIF_TERM> map_terms_vector;
  for (const auto &active_vstream_ref : active_pipeline_output_vstreams) {
    std::string active_name = active_vstream_ref.get().name();
    bool found = false;
    for (const auto &info_t : all_ng_output_infos) {
      if (std::string(info_t.name) == active_name) {
        map_terms_vector.push_back(
            build_detailed_vstream_info_map(env, info_t));
        found = true;
        break;
      }
    }
    if (!found) {
      ERL_NIF_TERM error_map = enif_make_new_map(env);
      enif_make_map_put(
          env, error_map, fine::encode(env, fine::Atom("error")),
          fine::encode(env, "Info not found for active stream: " + active_name),
          &error_map);
      map_terms_vector.push_back(error_map);
    }
  }
  ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(
      env, map_terms_vector.data(), map_terms_vector.size());
  return fine_ok(env, fine::Term(list_of_maps_term));
}

fine::Term infer(ErlNifEnv *env, fine::Term pipeline_term,
                 fine::Term input_data_term) {
  fine::ResourcePtr<InferPipelineResource> pipeline_res;
  try {
    pipeline_res = fine::decode<fine::ResourcePtr<InferPipelineResource>>(
        env, pipeline_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid pipeline resource");
  }
  std::map<std::string, std::string> input_map;
  try {
    input_map =
        fine::decode<std::map<std::string, std::string>>(env, input_data_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Input data must be a map");
  }
  auto input_vstreams = pipeline_res->pipeline->get_input_vstreams();
  auto output_vstreams = pipeline_res->pipeline->get_output_vstreams();
  std::map<std::string, hailort::MemoryView> input_data_mem_views;
  const size_t frames_count = 1;
  for (const auto &input_vstream : input_vstreams) {
    std::string name = input_vstream.get().name();
    auto it = input_map.find(name);
    if (it == input_map.end()) {
      return fine_error_string(env, "Missing input data for vstream: " + name);
    }
    std::string &binary = it->second;
    size_t expected_size = input_vstream.get().get_frame_size() * frames_count;
    if (binary.size() != expected_size) {
      return fine_error_string(
          env, "Invalid input data size for vstream " + name +
                   ". Expected: " + std::to_string(expected_size) +
                   ", Got: " + std::to_string(binary.size()));
    }
    input_data_mem_views.emplace(
        name, hailort::MemoryView(
                  const_cast<void *>(static_cast<const void *>(binary.data())),
                  binary.size()));
  }
  std::map<std::string, std::vector<uint8_t>> output_data;
  std::map<std::string, hailort::MemoryView> output_data_mem_views;
  for (const auto &output_vstream : output_vstreams) {
    std::string name = output_vstream.get().name();
    size_t frame_size = output_vstream.get().get_frame_size();
    output_data.emplace(name, std::vector<uint8_t>(frame_size * frames_count));
    auto &output_buffer = output_data[name];
    output_data_mem_views.emplace(
        name, hailort::MemoryView(output_buffer.data(), output_buffer.size()));
  }
  hailo_status status = pipeline_res->pipeline->infer(
      input_data_mem_views, output_data_mem_views, frames_count);
  if (status != HAILO_SUCCESS) {
    return fine_error_string(env, "Inference failed with status: " +
                                      std::to_string(status));
  }
  std::map<std::string, std::string> output_map;
  for (const auto &output_vstream : output_vstreams) {
    std::string name = output_vstream.get().name();
    const auto &output_buffer = output_data[name];
    output_map[name] =
        std::string(reinterpret_cast<const char *>(output_buffer.data()),
                    output_buffer.size());
  }
  return fine_ok(env, output_map);
}

// Creates a VDevice with scheduling configuration.
// Accepts an opts map with optional key:
//   scheduling_algorithm: :round_robin | :none
// If the key is absent, delegates to VDevice::create() to preserve
// backward-compatible defaults.
fine::Term create_vdevice_opts(ErlNifEnv *env, fine::Term opts_term) {
  ERL_NIF_TERM val;
  if (!enif_get_map_value(env, opts_term, fine::encode(env, fine::Atom("scheduling_algorithm")), &val)) {
    return create_vdevice(env);
  }

  fine::Atom alg;
  try {
    alg = fine::decode<fine::Atom>(env, fine::Term(val));
  } catch (...) {
    return fine_error_string(env, "Invalid scheduling_algorithm value");
  }

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

  auto vdevice_expected = hailort::VDevice::create(params);
  if (!vdevice_expected) {
    return fine_error_string(env, "Failed to create virtual device: " +
                                  std::to_string(vdevice_expected.status()));
  }
  auto resource = fine::make_resource<VDeviceResource>();
  resource->vdevice = std::move(vdevice_expected.value());
  return fine_ok(env, resource);
}

// Configures a network group and optionally sets scheduler timeout/threshold.
// Accepts an opts map with optional keys:
//   scheduler_timeout_ms: non-negative integer (milliseconds)
//   scheduler_threshold: non-negative integer (minimum frames before scheduling)
// Note: scheduling_algorithm is set at VDevice creation time (create_vdevice/1).
fine::Term configure_network_group_opts(ErlNifEnv *env,
                                        fine::ResourcePtr<VDeviceResource> vdevice_res,
                                        std::string hef_path,
                                        fine::Term opts_term) {
  auto hef = hailort::Hef::create(hef_path);
  if (!hef) {
    return fine_error_string(env, "Failed to load HEF file: " + std::to_string(hef.status()));
  }

  auto configure_params = vdevice_res->vdevice->create_configure_params(hef.value());
  if (!configure_params) {
    return fine_error_string(env, "Failed to create configure params: " +
                                  std::to_string(configure_params.status()));
  }

  auto network_groups = vdevice_res->vdevice->configure(hef.value(), configure_params.value());
  if (!network_groups) {
    return fine_error_string(env, "Failed to configure network groups: " +
                                  std::to_string(network_groups.status()));
  }
  if (network_groups->size() != 1) {
    return fine_error_string(env, "Invalid number of network groups: " +
                                  std::to_string(network_groups->size()));
  }

  auto ng = std::move(network_groups->at(0));

  ERL_NIF_TERM val;

  // Apply post-configure scheduler opts
  if (enif_get_map_value(env, opts_term, fine::encode(env, fine::Atom("scheduler_timeout_ms")), &val)) {
    uint64_t timeout_ms;
    try {
      timeout_ms = fine::decode<uint64_t>(env, fine::Term(val));
    } catch (...) {
      return fine_error_string(env, "Invalid scheduler_timeout_ms value");
    }
    hailo_status s = ng->set_scheduler_timeout(std::chrono::milliseconds(timeout_ms));
    if (s != HAILO_SUCCESS)
      return fine_error_string(env, "Failed to set scheduler timeout: " + std::to_string(s));
  }

  if (enif_get_map_value(env, opts_term, fine::encode(env, fine::Atom("scheduler_threshold")), &val)) {
    uint64_t threshold;
    try {
      threshold = fine::decode<uint64_t>(env, fine::Term(val));
    } catch (...) {
      return fine_error_string(env, "Invalid scheduler_threshold value");
    }
    hailo_status s = ng->set_scheduler_threshold(static_cast<uint32_t>(threshold));
    if (s != HAILO_SUCCESS)
      return fine_error_string(env, "Failed to set scheduler threshold: " + std::to_string(s));
  }

  auto resource = fine::make_resource<NetworkGroupResource>();
  resource->network_group = std::move(ng);
  resource->vdevice = vdevice_res->vdevice;
  return fine_ok(env, resource);
}

// Sets the scheduler timeout on a configured network group.
// Concurrent inference is dispatched to the hardware after this timeout
// even if the threshold has not been reached.
fine::Term set_scheduler_timeout(ErlNifEnv *env,
                                  fine::ResourcePtr<NetworkGroupResource> ng_res,
                                  uint64_t timeout_ms) {
  hailo_status s = ng_res->network_group->set_scheduler_timeout(
      std::chrono::milliseconds(timeout_ms));
  if (s != HAILO_SUCCESS)
    return fine_error_string(env, "Failed to set scheduler timeout: " + std::to_string(s));
  return fine::encode(env, fine::Atom("ok"));
}

// Sets the minimum number of frames that must be queued before the scheduler
// dispatches inference to the hardware.
fine::Term set_scheduler_threshold(ErlNifEnv *env,
                                    fine::ResourcePtr<NetworkGroupResource> ng_res,
                                    uint64_t threshold) {
  hailo_status s = ng_res->network_group->set_scheduler_threshold(
      static_cast<uint32_t>(threshold));
  if (s != HAILO_SUCCESS)
    return fine_error_string(env, "Failed to set scheduler threshold: " + std::to_string(s));
  return fine::encode(env, fine::Atom("ok"));
}

fine::Term hailo_version(ErlNifEnv *env) {
  return fine::encode(env, fine::Atom("hailo8"));
}

// Register NIF functions
FINE_NIF(hailo_version, 0);
FINE_NIF(create_pipeline, 1);
FINE_NIF(get_output_vstream_infos_from_pipeline, 1);
// infer: ERL_NIF_DIRTY_JOB_IO_BOUND (flags=2).
// Note: InferVStreams::infer() is not reentrant per-pipeline; concurrent
// Elixir processes can call infer() on different pipelines sharing the same
// VDevice (with ROUND_ROBIN scheduler), but a single pipeline serializes.
FINE_NIF(infer, 2);
FINE_NIF(get_input_vstream_infos_from_ng, 1);
FINE_NIF(get_output_vstream_infos_from_ng, 1);
FINE_NIF(get_input_vstream_infos_from_pipeline, 1);
FINE_NIF(set_scheduler_timeout, 0);
FINE_NIF(set_scheduler_threshold, 0);

// create_vdevice/1 and configure_network_group/3 use custom C++ names so
// they are registered manually below (api.ex always delegates through these).
static ERL_NIF_TERM create_vdevice_opts_nif(ErlNifEnv *env, int argc,
                                             const ERL_NIF_TERM argv[]) {
  return fine::nif(env, argc, argv, create_vdevice_opts);
}
static auto __nif_reg_vd1 = fine::Registration::register_nif(
    {"create_vdevice", fine::nif_arity(create_vdevice_opts), create_vdevice_opts_nif, 0});

static ERL_NIF_TERM configure_network_group_opts_nif(ErlNifEnv *env, int argc,
                                                      const ERL_NIF_TERM argv[]) {
  return fine::nif(env, argc, argv, configure_network_group_opts);
}
static auto __nif_reg_cng3 = fine::Registration::register_nif(
    {"configure_network_group", fine::nif_arity(configure_network_group_opts),
     configure_network_group_opts_nif, ERL_NIF_DIRTY_JOB_IO_BOUND});

FINE_INIT("Elixir.NxHailo.NIF");
