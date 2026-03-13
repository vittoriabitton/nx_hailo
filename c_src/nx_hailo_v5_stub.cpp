// Stub NIF for Hailo-10 when HailoRT is not available at compile time.
// Same NIF names as nx_hailo_v5.cpp but returns an error. Use when HAILORT_INCLUDE_DIR is not set.
// Set HAILORT_INCLUDE_DIR and recompile to build the real Hailo-10 NIF.

#include <fine.hpp>
#include <string>

static fine::Term fine_error_string(ErlNifEnv *env, const std::string &message) {
  std::tuple<fine::Atom, std::string> tagged_result(fine::Atom("error"), message);
  return fine::encode(env, tagged_result);
}

static const char *MSG =
  "Hailo-10 NIF not built: set HAILORT_INCLUDE_DIR (and HAILORT_LIB_DIR) to your HailoRT v5 install and recompile";

fine::Term create_vdevice(ErlNifEnv *env) {
  (void)env;
  return fine_error_string(env, MSG);
}

fine::Term configure_network_group(ErlNifEnv *env, fine::Term _, fine::Term __) {
  (void)env;
  (void)_;
  (void)__;
  return fine_error_string(env, MSG);
}

fine::Term create_pipeline(ErlNifEnv *env, fine::Term _) {
  (void)env;
  (void)_;
  return fine_error_string(env, MSG);
}

fine::Term get_input_vstream_infos_from_ng(ErlNifEnv *env, fine::Term _) {
  (void)env;
  (void)_;
  return fine_error_string(env, MSG);
}

fine::Term get_output_vstream_infos_from_ng(ErlNifEnv *env, fine::Term _) {
  (void)env;
  (void)_;
  return fine_error_string(env, MSG);
}

fine::Term get_input_vstream_infos_from_pipeline(ErlNifEnv *env, fine::Term _) {
  (void)env;
  (void)_;
  return fine_error_string(env, MSG);
}

fine::Term get_output_vstream_infos_from_pipeline(ErlNifEnv *env, fine::Term _) {
  (void)env;
  (void)_;
  return fine_error_string(env, MSG);
}

fine::Term infer(ErlNifEnv *env, fine::Term _, fine::Term __) {
  (void)env;
  (void)_;
  (void)__;
  return fine_error_string(env, MSG);
}

FINE_NIF(create_pipeline, 1);
FINE_NIF(get_output_vstream_infos_from_pipeline, 1);
FINE_NIF(infer, 2);
FINE_NIF(create_vdevice, 0);
FINE_NIF(configure_network_group, 2);
FINE_NIF(get_input_vstream_infos_from_ng, 1);
FINE_NIF(get_output_vstream_infos_from_ng, 1);
FINE_NIF(get_input_vstream_infos_from_pipeline, 1);

FINE_INIT("Elixir.NxHailo.NIF");
