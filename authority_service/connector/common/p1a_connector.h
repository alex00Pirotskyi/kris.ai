#pragma once
#include <stddef.h>
#include <stdint.h>
#if defined(_WIN32)
#define P1A_EXPORT __declspec(dllexport)
#else
#define P1A_EXPORT __attribute__((visibility("default")))
#endif
#ifdef __cplusplus
extern "C" {
#endif
P1A_EXPORT void* p1a_connector_alloc(intptr_t size);
P1A_EXPORT void p1a_connector_free(void* value);
P1A_EXPORT int32_t p1a_connector_configure(const uint8_t* json, intptr_t size);
P1A_EXPORT int32_t p1a_connector_request(const uint8_t* json, intptr_t size);
P1A_EXPORT intptr_t p1a_connector_response_size(void);
P1A_EXPORT intptr_t p1a_connector_copy_response(uint8_t* output, intptr_t capacity);
P1A_EXPORT void p1a_connector_close(void);
P1A_EXPORT uint32_t p1a_connector_abi_version(void);
#ifdef __cplusplus
}
#endif
