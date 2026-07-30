
cmake_minimum_required(VERSION 3.20)
project(kristin_p1a_smappservice_manager LANGUAGES OBJCXX)
add_executable(kristin_p1a_smappservice_manager smappservice_manager.mm)
target_compile_features(kristin_p1a_smappservice_manager PRIVATE cxx_std_20)
target_compile_options(kristin_p1a_smappservice_manager PRIVATE -Wall -Wextra -Werror -Wpedantic -fobjc-arc)
target_link_libraries(kristin_p1a_smappservice_manager PRIVATE "-framework Foundation" "-framework ServiceManagement")
