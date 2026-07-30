#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <string>
#include <string_view>
namespace kristin::p1a {
class sha256_state final {
 public:
  sha256_state(){reset();}
  void reset(){s_={0x6a09e667u,0xbb67ae85u,0x3c6ef372u,0xa54ff53au,0x510e527fu,0x9b05688cu,0x1f83d9abu,0x5be0cd19u};bits_=0;used_=0;}
  void update(const void* p,std::size_t n){const auto* b=static_cast<const std::uint8_t*>(p);for(std::size_t i=0;i<n;++i){buf_[used_++]=b[i];if(used_==64){block(buf_.data());bits_+=512;used_=0;}}}
  void update(std::string_view v){update(v.data(),v.size());}
  std::array<std::uint8_t,32> finish(){std::array<std::uint8_t,32>d{};std::size_t i=used_;buf_[i++]=0x80;if(i>56){while(i<64)buf_[i++]=0;block(buf_.data());i=0;}while(i<56)buf_[i++]=0;bits_+=used_*8;for(int sh=56;sh>=0;sh-=8)buf_[i++]=static_cast<std::uint8_t>(bits_>>sh);block(buf_.data());for(std::size_t w=0;w<8;++w){d[w*4]=static_cast<std::uint8_t>(s_[w]>>24);d[w*4+1]=static_cast<std::uint8_t>(s_[w]>>16);d[w*4+2]=static_cast<std::uint8_t>(s_[w]>>8);d[w*4+3]=static_cast<std::uint8_t>(s_[w]);}reset();return d;}
 private:
  static constexpr std::array<std::uint32_t,64> k_={0x428a2f98u,0x71374491u,0xb5c0fbcfu,0xe9b5dba5u,0x3956c25bu,0x59f111f1u,0x923f82a4u,0xab1c5ed5u,0xd807aa98u,0x12835b01u,0x243185beu,0x550c7dc3u,0x72be5d74u,0x80deb1feu,0x9bdc06a7u,0xc19bf174u,0xe49b69c1u,0xefbe4786u,0x0fc19dc6u,0x240ca1ccu,0x2de92c6fu,0x4a7484aau,0x5cb0a9dcu,0x76f988dau,0x983e5152u,0xa831c66du,0xb00327c8u,0xbf597fc7u,0xc6e00bf3u,0xd5a79147u,0x06ca6351u,0x14292967u,0x27b70a85u,0x2e1b2138u,0x4d2c6dfcu,0x53380d13u,0x650a7354u,0x766a0abbu,0x81c2c92eu,0x92722c85u,0xa2bfe8a1u,0xa81a664bu,0xc24b8b70u,0xc76c51a3u,0xd192e819u,0xd6990624u,0xf40e3585u,0x106aa070u,0x19a4c116u,0x1e376c08u,0x2748774cu,0x34b0bcb5u,0x391c0cb3u,0x4ed8aa4au,0x5b9cca4fu,0x682e6ff3u,0x748f82eeu,0x78a5636fu,0x84c87814u,0x8cc70208u,0x90befffau,0xa4506cebu,0xbef9a3f7u,0xc67178f2u};
  static std::uint32_t r(std::uint32_t x,std::uint32_t n){return(x>>n)|(x<<(32-n));}
  void block(const std::uint8_t* c){std::uint32_t w[64]{};for(std::size_t i=0;i<16;++i)w[i]=(std::uint32_t(c[i*4])<<24)|(std::uint32_t(c[i*4+1])<<16)|(std::uint32_t(c[i*4+2])<<8)|c[i*4+3];for(std::size_t i=16;i<64;++i){auto a=r(w[i-15],7)^r(w[i-15],18)^(w[i-15]>>3);auto b=r(w[i-2],17)^r(w[i-2],19)^(w[i-2]>>10);w[i]=w[i-16]+a+w[i-7]+b;}auto a=s_[0],b=s_[1],c0=s_[2],d=s_[3],e=s_[4],f=s_[5],g=s_[6],h=s_[7];for(std::size_t i=0;i<64;++i){auto s1=r(e,6)^r(e,11)^r(e,25);auto ch=(e&f)^((~e)&g);auto t1=h+s1+ch+k_[i]+w[i];auto s0=r(a,2)^r(a,13)^r(a,22);auto maj=(a&b)^(a&c0)^(b&c0);auto t2=s0+maj;h=g;g=f;f=e;e=d+t1;d=c0;c0=b;b=a;a=t1+t2;}s_[0]+=a;s_[1]+=b;s_[2]+=c0;s_[3]+=d;s_[4]+=e;s_[5]+=f;s_[6]+=g;s_[7]+=h;}
  std::array<std::uint32_t,8>s_{};std::array<std::uint8_t,64>buf_{};std::uint64_t bits_=0;std::size_t used_=0;
};
inline std::string hex_bytes(const std::uint8_t* p,std::size_t n){static constexpr char h[]="0123456789abcdef";std::string o(n*2,'0');for(std::size_t i=0;i<n;++i){o[i*2]=h[p[i]>>4];o[i*2+1]=h[p[i]&15];}return o;}
inline std::string sha256_hex(std::string_view v){sha256_state s;s.update(v);auto d=s.finish();return hex_bytes(d.data(),d.size());}
inline bool constant_time_equal(std::string_view a,std::string_view b){if(a.size()!=b.size())return false;unsigned char x=0;for(std::size_t i=0;i<a.size();++i)x|=static_cast<unsigned char>(a[i]^b[i]);return x==0;}
}
