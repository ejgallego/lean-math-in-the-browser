/* Private, sequential Emscripten bridge. The adapter owns the buffers and copies
   the result before release. Nat input is canonical decimal, including MR cases. */
#include <lean/lean.h>
#include <stdint.h>
#include <stdlib.h>

extern lean_object *fir_math_eval(uint32_t workload, lean_object *n);
static char *input = NULL;
static uint32_t capacity = 0;
static lean_object *result = NULL;

LEAN_EXPORT void fir_math_release(void) {
    free(input); input = NULL; capacity = 0;
    if (result) { lean_dec(result); result = NULL; }
}

LEAN_EXPORT uint32_t fir_math_input_alloc(uint32_t size) {
    fir_math_release();
    if (size == 0 || size > 4096) return 0;
    input = malloc((size_t)size + 1);
    if (!input) return 0;
    capacity = size; input[size] = 0;
    return (uint32_t)(uintptr_t)input;
}

LEAN_EXPORT uint32_t fir_math_run(uint32_t workload, uint32_t size) {
    if (!input || size == 0 || size != capacity || workload > 9) return 1;
    if (size > 1 && input[0] == '0') return 2;
    for (uint32_t i = 0; i < size; ++i)
        if (input[i] < '0' || input[i] > '9') return 2;
    if (result) { lean_dec(result); result = NULL; }
    input[size] = 0;
    result = fir_math_eval(workload, lean_cstr_to_nat(input));
    return 0;
}

LEAN_EXPORT uint32_t fir_math_result_ptr(void) {
    return result ? (uint32_t)(uintptr_t)lean_string_cstr(result) : 0;
}

LEAN_EXPORT uint32_t fir_math_result_len(void) {
    return result ? (uint32_t)(lean_string_size(result) - 1) : 0;
}
