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
FINE_RESOURCE(vdevice_resource, vdevice_resource_dtor);
FINE_RESOURCE(network_group_resource, network_group_resource_dtor);
FINE_RESOURCE(infer_pipeline_resource, infer_pipeline_resource_dtor);

// NIF function to load a network group from a HEF file
fine::Term load_network_group(ErlNifEnv *env, fine::Term hef_path_term) {
  // Get HEF file path from the input term
  std::string hef_path;
  if (!fine::get(env, hef_path_term, &hef_path)) {
    return fine::error(env, "Invalid HEF file path");
  }

  // Create a virtual device
  auto vdevice_expected = hailort::VDevice::create();
  if (!vdevice_expected) {
    return fine::error(env, "Failed to create virtual device: " +
                                std::to_string(vdevice_expected.status()));
  }
  auto vdevice = std::move(vdevice_expected.value());

  // Load the HEF file
  auto hef = hailort::Hef::create(hef_path);
  if (!hef) {
    return fine::error(env, "Failed to load HEF file: " +
                                std::to_string(hef.status()));
  }

  // Create configure params
  auto configure_params = vdevice->create_configure_params(hef.value());
  if (!configure_params) {
    return fine::error(env, "Failed to create configure params: " +
                                std::to_string(configure_params.status()));
  }

  // Configure the network groups
  auto network_groups =
      vdevice->configure(hef.value(), configure_params.value());
  if (!network_groups) {
    return fine::error(env, "Failed to configure network groups: " +
                                std::to_string(network_groups.status()));
  }

  // Check that we have exactly one network group
  if (network_groups->size() != 1) {
    return fine::error(env, "Invalid number of network groups: " +
                                std::to_string(network_groups->size()));
  }

  // Create a new resource for the NetworkGroup
  auto *res = new NetworkGroupResource;
  res->network_group = std::move(network_groups->at(0));
  res->vdevice = vdevice;

  // Return the resource term
  return fine::make_resource(env, network_group_resource, res);
}

// NIF function to create an inference pipeline from a network group
fine::Term create_pipeline(ErlNifEnv *env, fine::Term network_group_term) {
  // Get the network group resource from the input term
  NetworkGroupResource *ng_res;
  if (!fine::get_resource(env, network_group_term, network_group_resource,
                          &ng_res)) {
    return fine::error(env, "Invalid network group resource");
  }

  // Create input and output vstream params with default settings
  auto input_params = ng_res->network_group->make_input_vstream_params(
      {}, HAILO_FORMAT_TYPE_AUTO, HAILO_DEFAULT_VSTREAM_TIMEOUT_MS,
      HAILO_DEFAULT_VSTREAM_QUEUE_SIZE);
  if (!input_params) {
    return fine::error(env, "Failed to create input vstream params: " +
                                std::to_string(input_params.status()));
  }

  auto output_params = ng_res->network_group->make_output_vstream_params(
      {}, HAILO_FORMAT_TYPE_AUTO, HAILO_DEFAULT_VSTREAM_TIMEOUT_MS,
      HAILO_DEFAULT_VSTREAM_QUEUE_SIZE);
  if (!output_params) {
    return fine::error(env, "Failed to create output vstream params: " +
                                std::to_string(output_params.status()));
  }

  // Create the inference pipeline
  auto pipeline = hailort::InferVStreams::create(
      *ng_res->network_group, input_params.value(), output_params.value());
  if (!pipeline) {
    return fine::error(env, "Failed to create inference pipeline: " +
                                std::to_string(pipeline.status()));
  }

  // Create a new resource for the InferPipeline
  auto *res = new InferPipelineResource;
  res->pipeline = std::move(pipeline.value());
  res->network_group = ng_res->network_group;

  // Return the resource term
  return fine::make_resource(env, infer_pipeline_resource, res);
}

// Helper function to get vstream info as a map
fine::Term get_vstream_info(ErlNifEnv *env,
                            const hailort::OutputVStream &vstream) {
  fine::Term map = fine::make_map(env);
  map = fine::put(env, map, fine::make_atom(env, "name"),
                  fine::make_binary(env, vstream.name()));
  map = fine::put(env, map, fine::make_atom(env, "frame_size"),
                  fine::make_uint(env, vstream.get_frame_size()));
  return map;
}

// NIF function to get information about output vstreams
fine::Term get_output_vstream_info(ErlNifEnv *env, fine::Term pipeline_term) {
  // Get the pipeline resource from the input term
  InferPipelineResource *pipeline_res;
  if (!fine::get_resource(env, pipeline_term, infer_pipeline_resource,
                          &pipeline_res)) {
    return fine::error(env, "Invalid pipeline resource");
  }

  auto output_vstreams = pipeline_res->pipeline->get_output_vstreams();
  fine::Term result = fine::make_list(env, 0);

  for (auto it = output_vstreams.rbegin(); it != output_vstreams.rend(); ++it) {
    const auto &vstream = *it;
    fine::Term vstream_info = get_vstream_info(env, vstream);
    result = fine::cons(env, vstream_info, result);
  }

  return result;
}

// NIF function to run inference using a pipeline
fine::Term infer(ErlNifEnv *env, fine::Term pipeline_term,
                 fine::Term input_data_term) {
  // Get the pipeline resource from the input term
  InferPipelineResource *pipeline_res;
  if (!fine::get_resource(env, pipeline_term, infer_pipeline_resource,
                          &pipeline_res)) {
    return fine::error(env, "Invalid pipeline resource");
  }

  // Get the input data map from the input term
  std::map<std::string, fine::Term> input_map;
  if (!fine::get(env, input_data_term, &input_map)) {
    return fine::error(env, "Input data must be a map");
  }

  // Get the input and output vstreams
  auto input_vstreams = pipeline_res->pipeline->get_input_vstreams();
  auto output_vstreams = pipeline_res->pipeline->get_output_vstreams();

  // Set up input data map and memory views
  std::map<std::string, std::vector<uint8_t>> input_data;
  std::map<std::string, hailort::MemoryView> input_data_mem_views;

  const size_t frames_count = 1; // Process one frame at a time

  // Prepare input data for each input vstream
  for (const auto &input_vstream : input_vstreams) {
    std::string name = input_vstream.get().name();

    // Check if the input data contains this vstream name
    auto it = input_map.find(name);
    if (it == input_map.end()) {
      return fine::error(env, "Missing input data for vstream: " + name);
    }

    // Get binary data from Elixir term
    ErlNifBinary binary;
    if (!fine::get_binary(env, it->second, &binary)) {
      return fine::error(env, "Input data for vstream " + name +
                                  " must be a binary");
    }

    // Calculate expected size
    size_t expected_size = input_vstream.get().get_frame_size() * frames_count;
    if (binary.size != expected_size) {
      return fine::error(env,
                         "Invalid input data size for vstream " + name +
                             ". Expected: " + std::to_string(expected_size) +
                             ", Got: " + std::to_string(binary.size));
    }

    // Create memory view directly from binary data
    input_data_mem_views.emplace(name,
                                 hailort::MemoryView(binary.data, binary.size));
  }

  // Prepare output data map and memory views
  std::map<std::string, std::vector<uint8_t>> output_data;
  std::map<std::string, hailort::MemoryView> output_data_mem_views;

  // Allocate memory for each output vstream
  for (const auto &output_vstream : output_vstreams) {
    std::string name = output_vstream.get().name();
    size_t frame_size = output_vstream.get().get_frame_size();

    // Allocate buffer
    output_data.emplace(name, std::vector<uint8_t>(frame_size * frames_count));

    // Create memory view
    auto &output_buffer = output_data[name];
    output_data_mem_views.emplace(
        name, hailort::MemoryView(output_buffer.data(), output_buffer.size()));
  }

  // Run inference
  hailo_status status = pipeline_res->pipeline->infer(
      input_data_mem_views, output_data_mem_views, frames_count);

  if (status != HAILO_SUCCESS) {
    return fine::error(env, "Inference failed with status: " +
                                std::to_string(status));
  }

  // Prepare output data map to return to Elixir
  fine::Term output_map = fine::make_map(env);

  for (const auto &output_vstream : output_vstreams) {
    std::string name = output_vstream.get().name();
    const auto &output_buffer = output_data[name];

    // Create binary term from output buffer
    fine::Term binary_term =
        fine::make_binary(env, output_buffer.data(), output_buffer.size());

    // Add to output map
    output_map =
        fine::put(env, output_map, fine::make_binary(env, name), binary_term);
  }

  return output_map;
}

// Register NIF functions
FINE_NIF(load_network_group, 1);
FINE_NIF(create_pipeline, 1);
FINE_NIF(get_output_vstream_info, 1);
FINE_NIF(infer, 2);

// Old code - keeping for reference
// fine::Term identity(ErlNifEnv *env, fine::Term term) { return term; }
// FINE_NIF(identity, 1);

FINE_INIT("Elixir.NxHailo.NIF");