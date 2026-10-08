#include <iostream>
#include <string>
#include "snappy.h"

// Declare the exact namespace used by the prebuilt Firebase/LevelDB objects.
// A codec built in the default namespace must fail to link this test.
namespace f_b_snappy {
void RawCompress(const char*, size_t, char*, size_t*);
size_t MaxCompressedLength(size_t);
bool RawUncompress(const char*, size_t, char*);
bool GetUncompressedLength(const char*, size_t, size_t*);
}

int main() {
  const std::string abi_input = "Firebase LevelDB namespace compatibility";
  std::string abi_compressed(f_b_snappy::MaxCompressedLength(abi_input.size()), '\0');
  size_t compressed_size = 0;
  f_b_snappy::RawCompress(abi_input.data(), abi_input.size(),
                         &abi_compressed[0], &compressed_size);
  size_t decoded_size = 0;
  if (!f_b_snappy::GetUncompressedLength(abi_compressed.data(), compressed_size,
                                        &decoded_size) ||
      decoded_size != abi_input.size()) return 4;
  std::string abi_decoded(decoded_size, '\0');
  if (!f_b_snappy::RawUncompress(abi_compressed.data(), compressed_size,
                                &abi_decoded[0]) ||
      abi_decoded != abi_input) return 5;
  // Known raw Snappy stream: length=5, literal length=5, "hello".
  const std::string fixture("\x05\x10hello", 7);
  std::string decoded;
  if (!snappy::Uncompress(fixture.data(), fixture.size(), &decoded) ||
      decoded != "hello") return 1;
  for (size_t length : {0, 1, 7, 64, 4096, 65536, 1048576}) {
    for (int pattern = 0; pattern < 3; ++pattern) {
      std::string input(length, 'x');
      unsigned int random = 12345;
      for (size_t i = 0; i < length; ++i) {
        random = random * 1664525u + 1013904223u;
        if (pattern == 1) input[i] = static_cast<char>(i % 251);
        if (pattern == 2) input[i] = static_cast<char>(random >> 24);
      }
      std::string compressed;
      snappy::Compress(input.data(), input.size(), &compressed);
      if (!snappy::Uncompress(compressed.data(), compressed.size(), &decoded) ||
          decoded != input) return 2;
      if (compressed.size() > 1 && snappy::IsValidCompressedBuffer(
          compressed.data(), compressed.size() - 1)) return 3;
    }
  }
  std::cout << "Firebase namespace ABI, Snappy fixture and 21 codec cases passed\n";
  return 0;
}
