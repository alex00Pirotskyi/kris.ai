
#include "p1a_connector.h"
#include <fstream>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

static std::string read_all(const std::string& path) {
  std::istream* stream = &std::cin; std::ifstream file;
  if (!path.empty() && path != "-") { file.open(path, std::ios::binary); if (!file) throw std::runtime_error("file_open_failed:" + path); stream=&file; }
  return std::string(std::istreambuf_iterator<char>(*stream), std::istreambuf_iterator<char>());
}
static std::string response() {
  const auto size=p1a_connector_response_size(); if(size<=0||size>16*1024*1024) throw std::runtime_error("connector_response_size_invalid");
  std::vector<unsigned char> out(static_cast<std::size_t>(size));
  if(p1a_connector_copy_response(out.data(),size)!=size) throw std::runtime_error("connector_response_copy_failed");
  return std::string(reinterpret_cast<const char*>(out.data()),out.size());
}
int main(int argc,char**argv) try {
  if(argc==2&&std::string(argv[1])=="--source-self-test"){
    if(p1a_connector_abi_version()!=0x00020000u) throw std::runtime_error("connector_abi_version_invalid");
    std::cout<<"{\"status\":\"passed\",\"connectorAbi\":\"2.0.0\",\"completionEligible\":false}\n";return 0;
  }
  std::string config,request;
  for(int i=1;i<argc;++i){std::string a=argv[i];auto take=[&](){if(++i>=argc)throw std::runtime_error("argument_value_missing");return std::string(argv[i]);};if(a=="--config-json")config=take();else if(a=="--config-file")config=read_all(take());else if(a=="--request-json")request=take();else if(a=="--request-file")request=read_all(take());else if(a=="--request-stdin")request=read_all("-");else throw std::runtime_error("unknown_argument:"+a);}
  if(config.empty()||request.empty())throw std::runtime_error("config_and_request_required");
  if(p1a_connector_configure(reinterpret_cast<const uint8_t*>(config.data()),static_cast<intptr_t>(config.size()))!=0){std::cerr<<response()<<"\n";return 2;}
  const auto rc=p1a_connector_request(reinterpret_cast<const uint8_t*>(request.data()),static_cast<intptr_t>(request.size()));std::cout<<response()<<"\n";p1a_connector_close();return rc==0?0:3;
 } catch(const std::exception&e){std::cerr<<"P1A connector CLI fatal: "<<e.what()<<"\n";return 1;}
