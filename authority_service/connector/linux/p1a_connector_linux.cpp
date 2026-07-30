
#include "../common/p1a_connector.h"
#include "../../native/common/strict_json.hpp"
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>
#include <array>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <stdexcept>
#include <string>
#include <string_view>

namespace {namespace j=kristin::p1a::json;std::mutex g_mu;std::string g_address,g_response;std::size_t g_max=4*1024*1024;
void set_error(std::string_view code){g_response=j::canonical(j::value(j::value::object{{"schemaVersion",j::value("2.0.0")},{"status",j::value("transport-error")},{"errorCode",j::value(std::string(code))}}));}
void send_all(int fd,const void*data,std::size_t size){auto*p=static_cast<const unsigned char*>(data);while(size){auto n=::send(fd,p,size,MSG_NOSIGNAL);if(n<0){if(errno==EINTR)continue;throw std::runtime_error("connector_send_failed");}if(n==0)throw std::runtime_error("connector_send_closed");p+=n;size-=static_cast<std::size_t>(n);}}
void recv_all(int fd,void*data,std::size_t size){auto*p=static_cast<unsigned char*>(data);while(size){auto n=::recv(fd,p,size,0);if(n<0){if(errno==EINTR)continue;throw std::runtime_error("connector_recv_failed");}if(n==0)throw std::runtime_error("connector_recv_closed");p+=n;size-=static_cast<std::size_t>(n);}}
std::string transact(std::string_view request){if(g_address.empty())throw std::runtime_error("connector_not_configured");int fd=::socket(AF_UNIX,SOCK_STREAM|SOCK_CLOEXEC,0);if(fd<0)throw std::runtime_error("connector_socket_failed");struct closer{int fd;~closer(){if(fd>=0)::close(fd);}}c{fd};sockaddr_un addr{};addr.sun_family=AF_UNIX;if(g_address.size()>=sizeof(addr.sun_path))throw std::runtime_error("connector_address_too_long");std::memcpy(addr.sun_path,g_address.c_str(),g_address.size()+1);if(::connect(fd,reinterpret_cast<sockaddr*>(&addr),sizeof(addr))!=0)throw std::runtime_error("connector_connect_denied");std::array<unsigned char,4>h{static_cast<unsigned char>(request.size()>>24),static_cast<unsigned char>(request.size()>>16),static_cast<unsigned char>(request.size()>>8),static_cast<unsigned char>(request.size())};send_all(fd,h.data(),h.size());send_all(fd,request.data(),request.size());recv_all(fd,h.data(),h.size());std::uint32_t n=(std::uint32_t(h[0])<<24)|(std::uint32_t(h[1])<<16)|(std::uint32_t(h[2])<<8)|h[3];if(n==0||n>g_max)throw std::runtime_error("connector_response_budget_exceeded");std::string out(n,'\0');recv_all(fd,out.data(),out.size());return out;}
}
extern "C" {
void* p1a_connector_alloc(intptr_t n){return n>0&&n<=64*1024*1024?std::malloc(static_cast<std::size_t>(n)):nullptr;}void p1a_connector_free(void*v){std::free(v);}uint32_t p1a_connector_abi_version(void){return 0x00020000u;}
int32_t p1a_connector_configure(const uint8_t*data,intptr_t size){std::lock_guard<std::mutex>l(g_mu);try{if(!data||size<=0||size>1024*1024)throw std::runtime_error("connector_config_size_invalid");auto v=j::parse(std::string_view(reinterpret_cast<const char*>(data),static_cast<std::size_t>(size)));const auto&o=v.as_object();if(j::required_string(o,"schemaVersion")!="2.0.0")throw std::runtime_error("connector_config_schema_invalid");g_address=j::required_string(o,"address");auto n=j::required_int(o,"maxResponseBytes");if(g_address.empty()||n<65536||n>16*1024*1024)throw std::runtime_error("connector_config_invalid");g_max=static_cast<std::size_t>(n);g_response=j::canonical(j::value(j::value::object{{"status",j::value("configured")}}));return 0;}catch(const std::exception&e){set_error(e.what());return 1;}}
int32_t p1a_connector_request(const uint8_t*data,intptr_t size){std::lock_guard<std::mutex>l(g_mu);try{if(!data||size<=0||static_cast<std::size_t>(size)>g_max)throw std::runtime_error("connector_request_size_invalid");g_response=transact(std::string_view(reinterpret_cast<const char*>(data),static_cast<std::size_t>(size)));auto value=j::parse(g_response);return value.as_object().contains("status")&&j::required_string(value.as_object(),"status")=="denied"?2:0;}catch(const std::exception&e){set_error(e.what());return 1;}}
intptr_t p1a_connector_response_size(void){std::lock_guard<std::mutex>l(g_mu);return static_cast<intptr_t>(g_response.size());}intptr_t p1a_connector_copy_response(uint8_t*out,intptr_t cap){std::lock_guard<std::mutex>l(g_mu);if(!out||cap<0||static_cast<std::size_t>(cap)<g_response.size())return-1;std::memcpy(out,g_response.data(),g_response.size());return static_cast<intptr_t>(g_response.size());}void p1a_connector_close(void){std::lock_guard<std::mutex>l(g_mu);g_address.clear();g_response.clear();g_max=4*1024*1024;}
}
