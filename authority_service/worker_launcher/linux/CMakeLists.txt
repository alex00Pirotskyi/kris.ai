
cmake_minimum_required(VERSION 3.20)
project(kristin_p2_worker_launcher_linux LANGUAGES CXX)
add_executable(kristin_p2_worker_launcher restricted_worker_launcher_linux.cpp)
target_compile_features(kristin_p2_worker_launcher PRIVATE cxx_std_20)
target_include_directories(kristin_p2_worker_launcher PRIVATE ../../native/common)
target_compile_options(kristin_p2_worker_launcher PRIVATE -Wall -Wextra -Werror -Wpedantic)
