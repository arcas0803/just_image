// Copyright (c) 2026 just_image contributors.
// SPDX-License-Identifier: MIT

#ifndef JUST_IMAGE_H_
#define JUST_IMAGE_H_

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define JUST_IMAGE_ABI_VERSION 1

typedef struct FfiResult {
  uint8_t *data;
  size_t len;
  uint32_t width;
  uint32_t height;
  char *error;
} FfiResult;

uint32_t rust_abi_version(void);
FfiResult rust_process_pipeline(const uint8_t *input_ptr, size_t input_len,
                                const char *config_json,
                                const uint8_t *watermark_ptr,
                                size_t watermark_len);
void rust_free_buffer(uint8_t *ptr, size_t len);
void rust_free_error(char *ptr);
char *rust_version(void);
void rust_free_string(char *ptr);
FfiResult rust_image_info(const uint8_t *input_ptr, size_t input_len);
FfiResult rust_blurhash_encode(const uint8_t *input_ptr, size_t input_len,
                               uint32_t components_x,
                               uint32_t components_y);
FfiResult rust_blurhash_decode(const char *hash_ptr, uint32_t width,
                               uint32_t height);
char *rust_available_filters(void);

#ifdef __cplusplus
}
#endif

#endif  // JUST_IMAGE_H_
