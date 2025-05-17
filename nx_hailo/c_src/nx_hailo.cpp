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
  return fine::Ok(fine::encode(env, resource));
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
  return fine::encode(env, resource);
}

// Helper function to get vstream info as a map
fine::Term get_vstream_info(ErlNifEnv *env,
                            const hailort::OutputVStream &vstream) {
  // std::map<std::string, uint64_t> map;
  // map["name"] = 0; // Will be replaced below
  // map["frame_size"] = vstream.get_frame_size();
  // // For name, we need to encode as binary, so we will build the map manually
  // ERL_NIF_TERM result_map;
  // enif_make_new_map(env, &result_map);
  // ERL_NIF_TERM name_key = fine::encode(env, std::string("name"));
  // ERL_NIF_TERM name_val = fine::encode(env, vstream.name());
  // enif_make_map_put(env, result_map, name_key, name_val, &result_map);
  // ERL_NIF_TERM frame_size_key = fine::encode(env, std::string("frame_size"));
  // ERL_NIF_TERM frame_size_val =
  //     fine::encode(env, static_cast<uint64_t>(vstream.get_frame_size()));
  // enif_make_map_put(env, result_map, frame_size_key, frame_size_val,
  //                   &result_map);
  return fine::encode(env, fine::Ok());
}

// NIF function to get information about output vstreams
fine::Term get_output_vstream_info(ErlNifEnv *env, fine::Term pipeline_term) {
  // Get the pipeline resource from the input term
  fine::ResourcePtr<InferPipelineResource> pipeline_res;
  try {
    pipeline_res = fine::decode<fine::ResourcePtr<InferPipelineResource>>(
        env, pipeline_term);
  } catch (const std::exception &e) {
    return fine_error_string(env, "Invalid pipeline resource");
  }

  auto output_vstreams = pipeline_res->pipeline->get_output_vstreams();
  std::vector<ERL_NIF_TERM> result;
  for (const auto &vstream : output_vstreams) {
    result.push_back(get_vstream_info(env, vstream));
  }
  return fine::encode(env, result);
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
FINE_NIF(get_output_vstream_info, 1);
FINE_NIF(infer, 2);

FINE_INIT("Elixir.NxHailo.NIF");