#include "hailo/hailort.hpp"
#include <fine.hpp>
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
  std::tuple<fine::Atom, std::string> tagged_result(fine::Atom("error"), message);
  return fine::encode(env, tagged_result);
}

template <typename T> fine::Term fine_ok(ErlNifEnv *env, T value) {
  std::tuple<fine::Atom, T> tagged_result(fine::Atom("ok"), value);
  return fine::encode(env, tagged_result);
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

// NIF function to load a network group from a HEF file
fine::Term load_network_group(ErlNifEnv *env, fine::Term hef_path_term) {
  // Get HEF file path from the input term
  std::string hef_path;
  try {
    hef_path = fine::decode<std::string>(env, hef_path_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid HEF file path");
  }

  // Create a virtual device
  auto vdevice_expected = hailort::VDevice::create();
  if (!vdevice_expected) {
    return fine_error_string(env,
                             "Failed to create virtual device: " +
                                 std::to_string(vdevice_expected.status()));
  }
  auto vdevice = std::move(vdevice_expected.value());

  // Load the HEF file
  auto hef = hailort::Hef::create(hef_path);
  if (!hef) {
    return fine_error_string(env, "Failed to load HEF file: " +
                                      std::to_string(hef.status()));
  }

  // Create configure params
  auto configure_params = vdevice->create_configure_params(hef.value());
  if (!configure_params) {
    return fine_error_string(env,
                             "Failed to create configure params: " +
                                 std::to_string(configure_params.status()));
  }

  // Configure the network groups
  auto network_groups =
      vdevice->configure(hef.value(), configure_params.value());
  if (!network_groups) {
    return fine_error_string(env, "Failed to configure network groups: " +
                                      std::to_string(network_groups.status()));
  }

  // Check that we have exactly one network group
  if (network_groups->size() != 1) {
    return fine_error_string(env, "Invalid number of network groups: " +
                                      std::to_string(network_groups->size()));
  }

  // Create a new resource for the NetworkGroup
  auto resource = fine::make_resource<NetworkGroupResource>();
  resource->network_group = std::move(network_groups->at(0));
  resource->vdevice = std::move(vdevice);

  // Return the resource term
  return fine_ok(env, resource);
}

// NIF function to configure a network group using an existing VDevice
fine::Term configure_network_group(ErlNifEnv *env,
                                   fine::Term vdevice_resource_term,
                                   fine::Term hef_path_term) {
  fine::ResourcePtr<VDeviceResource> vdevice_res;
  try {
    vdevice_res =
        fine::decode<fine::ResourcePtr<VDeviceResource>>(env, vdevice_resource_term);
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
  resource->vdevice = vdevice_res->vdevice; // Share the vdevice
  return fine_ok(env, resource);
}

// NIF function to create an inference pipeline from a network group
fine::Term create_pipeline(ErlNifEnv *env, fine::Term network_group_term) {
  // Get the network group resource from the input term
  fine::ResourcePtr<NetworkGroupResource> ng_res;
  try {
    ng_res = fine::decode<fine::ResourcePtr<NetworkGroupResource>>(
        env, network_group_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid network group resource");
  }

  // Create input and output vstream params with default settings
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

  // Create the inference pipeline
  auto pipeline = hailort::InferVStreams::create(
      *ng_res->network_group, input_params.value(), output_params.value());
  if (!pipeline) {
    return fine_error_string(env, "Failed to create inference pipeline: " +
                                      std::to_string(pipeline.status()));
  }

  // Create a new resource for the InferPipeline
  auto resource = fine::make_resource<InferPipelineResource>();
  resource->pipeline =
      std::make_shared<hailort::InferVStreams>(std::move(pipeline.value()));
  resource->network_group = ng_res->network_group;

  // Return the resource term
  return fine_ok(env, resource);
}

// Helper function to construct an Erlang map for vstream info
ERL_NIF_TERM make_vstream_info_erlang_map(ErlNifEnv *env, const std::string& name, uint64_t frame_size) {
    ERL_NIF_TERM map_term;
    map_term = enif_make_new_map(env);

    ERL_NIF_TERM name_key_term = fine::encode(env, std::string("name"));
    ERL_NIF_TERM name_val_term = fine::encode(env, name);
    enif_make_map_put(env, map_term, name_key_term, name_val_term, &map_term);

    ERL_NIF_TERM frame_size_key_term = fine::encode(env, std::string("frame_size"));
    ERL_NIF_TERM frame_size_val_term = fine::encode(env, frame_size);
    enif_make_map_put(env, map_term, frame_size_key_term, frame_size_val_term, &map_term);

    return map_term;
}

// Helper function to get vstream info as a map (overload for InputVStream)
ERL_NIF_TERM get_vstream_info_map(ErlNifEnv *env,
                                const hailort::InputVStream &vstream) {
  return make_vstream_info_erlang_map(env, vstream.name(), static_cast<uint64_t>(vstream.get_frame_size()));
}

// Helper function to get vstream info as a map (overload for OutputVStream)
ERL_NIF_TERM get_vstream_info_map(ErlNifEnv *env,
                                const hailort::OutputVStream &vstream) {
  return make_vstream_info_erlang_map(env, vstream.name(), static_cast<uint64_t>(vstream.get_frame_size()));
}

// NIF function to get information about input vstreams from a NetworkGroup
fine::Term get_input_vstream_infos_from_ng(ErlNifEnv *env, fine::Term network_group_term) {
  fine::ResourcePtr<NetworkGroupResource> ng_res;
  try {
    ng_res = fine::decode<fine::ResourcePtr<NetworkGroupResource>>(env, network_group_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid network group resource for getting input vstream infos");
  }

  auto vstream_infos = ng_res->network_group->get_input_vstream_infos();
  if (!vstream_infos) {
      return fine_error_string(env, "Failed to get input vstream infos from network group: " + std::to_string(vstream_infos.status()));
  }

  std::vector<ERL_NIF_TERM> map_terms_vector;
  for (const auto &info : vstream_infos.value()) {
    uint32_t frame_size = hailort::HailoRTCommon::get_frame_size(info.shape, info.format);
    map_terms_vector.push_back(make_vstream_info_erlang_map(env, info.name, static_cast<uint64_t>(frame_size)));
  }
  ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(env, map_terms_vector.data(), map_terms_vector.size());
  return fine_ok(env, list_of_maps_term);
}

// NIF function to get information about output vstreams from a NetworkGroup
fine::Term get_output_vstream_infos_from_ng(ErlNifEnv *env, fine::Term network_group_term) {
  fine::ResourcePtr<NetworkGroupResource> ng_res;
  try {
    ng_res = fine::decode<fine::ResourcePtr<NetworkGroupResource>>(env, network_group_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid network group resource for getting output vstream infos");
  }

  auto vstream_infos = ng_res->network_group->get_output_vstream_infos();
  if (!vstream_infos) {
      return fine_error_string(env, "Failed to get output vstream infos from network group: " + std::to_string(vstream_infos.status()));
  }

  std::vector<ERL_NIF_TERM> map_terms_vector;
  for (const auto &info : vstream_infos.value()) {
    uint32_t frame_size = hailort::HailoRTCommon::get_frame_size(info.shape, info.format);
    map_terms_vector.push_back(make_vstream_info_erlang_map(env, info.name, static_cast<uint64_t>(frame_size)));
  }
  ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(env, map_terms_vector.data(), map_terms_vector.size());
  return fine_ok(env, list_of_maps_term);
}

// NIF function to get information about input vstreams from a pipeline
fine::Term get_input_vstream_infos_from_pipeline(ErlNifEnv *env, fine::Term pipeline_term) {
    fine::ResourcePtr<InferPipelineResource> pipeline_res;
    try {
        pipeline_res = fine::decode<fine::ResourcePtr<InferPipelineResource>>(env, pipeline_term);
    } catch (const std::exception &e) {
        return fine_error_string(env, "Invalid pipeline resource for getting input vstream infos");
    }

    auto input_vstreams = pipeline_res->pipeline->get_input_vstreams();
    std::vector<ERL_NIF_TERM> map_terms_vector;
    for (const auto &vstream : input_vstreams) {
        map_terms_vector.push_back(get_vstream_info_map(env, vstream.get()));
    }
    ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(env, map_terms_vector.data(), map_terms_vector.size());

    return fine_ok(env, fine::Term(list_of_maps_term));
}

// NIF function to get information about output vstreams
fine::Term get_output_vstream_infos_from_pipeline(ErlNifEnv *env, fine::Term pipeline_term) {
  fine::ResourcePtr<InferPipelineResource> pipeline_res;
  try {
    pipeline_res = fine::decode<fine::ResourcePtr<InferPipelineResource>>(env, pipeline_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid pipeline resource for getting output vstream infos");
  }

  auto output_vstreams = pipeline_res->pipeline->get_output_vstreams();
  std::vector<ERL_NIF_TERM> map_terms_vector;
    for (const auto &vstream : output_vstreams) {
        map_terms_vector.push_back(get_vstream_info_map(env, vstream.get()));
    }
  ERL_NIF_TERM list_of_maps_term = enif_make_list_from_array(env, map_terms_vector.data(), map_terms_vector.size());
  return fine_ok(env, fine::Term(list_of_maps_term));
}

// NIF function to run inference using a pipeline
fine::Term infer(ErlNifEnv *env, fine::Term pipeline_term,
                 fine::Term input_data_term) {
  // Get the pipeline resource from the input term
  fine::ResourcePtr<InferPipelineResource> pipeline_res;
  try {
    pipeline_res = fine::decode<fine::ResourcePtr<InferPipelineResource>>(
        env, pipeline_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid pipeline resource");
  }

  // Get the input data map from the input term
  std::map<std::string, ERL_NIF_TERM> input_map;
  try {
    input_map =
        fine::decode<std::map<std::string, ERL_NIF_TERM>>(env, input_data_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Input data must be a map");
  }

  // Get the input and output vstreams
  auto input_vstreams = pipeline_res->pipeline->get_input_vstreams();
  auto output_vstreams = pipeline_res->pipeline->get_output_vstreams();

  // Set up input data map and memory views
  std::map<std::string, hailort::MemoryView> input_data_mem_views;
  const size_t frames_count = 1; // Process one frame at a time

  // Prepare input data for each input vstream
  for (const auto &input_vstream : input_vstreams) {
    std::string name = input_vstream.get().name();
    auto it = input_map.find(name);
    if (it == input_map.end()) {
      return fine_error_string(env, "Missing input data for vstream: " + name);
    }
    ErlNifBinary binary;
    if (!enif_inspect_binary(env, it->second, &binary)) {
      return fine_error_string(env, "Input data for vstream " + name +
                                        " must be a binary");
    }
    size_t expected_size = input_vstream.get().get_frame_size() * frames_count;
    if (binary.size != expected_size) {
      return fine_error_string(
          env, "Invalid input data size for vstream " + name +
                   ". Expected: " + std::to_string(expected_size) +
                   ", Got: " + std::to_string(binary.size));
    }
    input_data_mem_views.emplace(name,
                                 hailort::MemoryView(binary.data, binary.size));
  }

  // Prepare output data map and memory views
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

  // Run inference
  hailo_status status = pipeline_res->pipeline->infer(
      input_data_mem_views, output_data_mem_views, frames_count);
  if (status != HAILO_SUCCESS) {
    return fine_error_string(env, "Inference failed with status: " +
                                      std::to_string(status));
  }

  // Prepare output data map to return to Elixir
  std::map<std::string, ERL_NIF_TERM> output_map;
  for (const auto &output_vstream : output_vstreams) {
    std::string name = output_vstream.get().name();
    const auto &output_buffer = output_data[name];
    ERL_NIF_TERM binary_term;
    unsigned char *bin = (unsigned char *)enif_make_new_binary(
        env, output_buffer.size(), &binary_term);
    memcpy(bin, output_buffer.data(), output_buffer.size());
    output_map[name] = binary_term;
  }
  return fine::encode(env, output_map);
}

// Register NIF functions
FINE_NIF(load_network_group, 1);
FINE_NIF(create_pipeline, 1);
FINE_NIF(get_output_vstream_infos_from_pipeline, 1);
FINE_NIF(infer, 2);
FINE_NIF(create_vdevice, 0);
FINE_NIF(configure_network_group, 2);
FINE_NIF(get_input_vstream_infos_from_ng, 1);
FINE_NIF(get_output_vstream_infos_from_ng, 1);
FINE_NIF(get_input_vstream_infos_from_pipeline, 1);

FINE_INIT("Elixir.NxHailo.NIF");
