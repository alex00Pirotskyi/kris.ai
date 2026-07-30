#pragma once

#include <algorithm>
#include <cctype>
#include <string_view>

namespace kristin::p1a {

inline bool valid_identifier(std::string_view value) {
  if (value.empty() || value.size() > 192) return false;
  return std::all_of(value.begin(), value.end(), [](unsigned char c) {
    return std::isalnum(c) || c == '_' || c == '.' || c == ':' || c == '@' || c == '-';
  });
}

inline bool valid_hex64(std::string_view value) {
  return value.size() == 64 && std::all_of(value.begin(), value.end(), [](unsigned char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f');
  });
}

}  // namespace kristin::p1a
