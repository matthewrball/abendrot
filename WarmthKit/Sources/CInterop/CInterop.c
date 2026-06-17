/*
 * CInterop translation unit.
 *
 * Intentionally (almost) empty: this target declares private-symbol type SHAPES only and
 * links nothing private. The single no-op symbol below gives the C target a non-empty
 * object file so SwiftPM has something to compile and archive. All real private symbols are
 * resolved at RUNTIME via dlopen()/dlsym() in the Swift system layers.
 */

#include "CInterop.h"

/* A linker anchor so this translation unit is never empty across toolchains. */
int wk_cinterop_present(void) { return 1; }
