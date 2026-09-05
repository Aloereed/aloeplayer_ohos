#pragma once
#include <cstdint>
#include <string>

// Descriptor stays owned by the caller until the synchronous operation returns.
int64_t probeDurationFd(int fd);
std::string probeHdrFd(int fd);
std::string thumbnailFromFd(int fd);
