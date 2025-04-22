#include <fine.hpp>

fine::Term identity(ErlNifEnv *env, fine::Term term) { return term; }

FINE_NIF(identity, 1);

FINE_INIT("Elixir.NxHailo.NIF");