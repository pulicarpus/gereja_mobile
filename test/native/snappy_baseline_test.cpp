#include <iostream>
#include <string>
#include "snappy.h"

int main() {
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
  std::cout << "Snappy fixture and 21 compression/decompression cases passed\n";
  return 0;
}
