#pragma once

// Minimal allocation-bounded RFC 8259 parser/canonicalizer used by the P1A
// service. It deliberately rejects duplicate object keys and non-canonical
// numbers. The implementation is self-contained so the authority binary does
// not acquire a platform package-manager dependency.

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <map>
#include <stdexcept>
#include <string>
#include <string_view>
#include <variant>
#include <vector>
#include <utility>

namespace kristin::p1a::json {

class error final : public std::runtime_error {
 public: explicit error(const std::string& value) : std::runtime_error(value) {}
};

struct value {
  using array = std::vector<value>;
  using object = std::map<std::string, value, std::less<>>;
  std::variant<std::nullptr_t,bool,std::int64_t,std::string,array,object> data{nullptr};
  value()=default;
  value(std::nullptr_t):data(nullptr){}
  explicit value(bool v):data(v){}
  explicit value(std::int64_t v):data(v){}
  explicit value(int v):data(static_cast<std::int64_t>(v)){}
  value(const char* v):data(v ? std::string(v) : throw error("json_null_c_string")){}
  value(std::string_view v):data(std::string(v)){}
  value(std::string v):data(std::move(v)){}
  value(array v):data(std::move(v)){}
  value(object v):data(std::move(v)){}
  bool is_object()const{return std::holds_alternative<object>(data);} bool is_array()const{return std::holds_alternative<array>(data);}
  bool is_string()const{return std::holds_alternative<std::string>(data);} bool is_int()const{return std::holds_alternative<std::int64_t>(data);}
  bool is_bool()const{return std::holds_alternative<bool>(data);} bool is_null()const{return std::holds_alternative<std::nullptr_t>(data);}
  const object& as_object()const{if(!is_object())throw error("json_object_required");return std::get<object>(data);} object& as_object(){if(!is_object())throw error("json_object_required");return std::get<object>(data);}
  const array& as_array()const{if(!is_array())throw error("json_array_required");return std::get<array>(data);} const std::string& as_string()const{if(!is_string())throw error("json_string_required");return std::get<std::string>(data);}
  std::int64_t as_int()const{if(!is_int())throw error("json_integer_required");return std::get<std::int64_t>(data);} bool as_bool()const{if(!is_bool())throw error("json_boolean_required");return std::get<bool>(data);}
  const value& at(std::string_view key)const{const auto& o=as_object();auto i=o.find(key);if(i==o.end())throw error("json_field_missing:"+std::string(key));return i->second;}
  const value* find(std::string_view key)const{if(!is_object())return nullptr;const auto& o=std::get<object>(data);auto i=o.find(key);return i==o.end()?nullptr:&i->second;}
};

class parser final {
 public:
  explicit parser(std::string_view input):input_(input){}
  value parse(){skip();auto v=parse_value(0);skip();if(pos_!=input_.size())fail("trailing_data");return v;}
 private:
  std::string_view input_;std::size_t pos_=0;static constexpr std::size_t max_depth=64;
  [[noreturn]] void fail(const char* code)const{throw error(std::string("json_")+code+"_at_"+std::to_string(pos_));}
  void skip(){while(pos_<input_.size()&&(input_[pos_]==' '||input_[pos_]=='\n'||input_[pos_]=='\r'||input_[pos_]=='\t'))++pos_;}
  char take(){if(pos_>=input_.size())fail("eof");return input_[pos_++];}
  bool consume(char c){if(pos_<input_.size()&&input_[pos_]==c){++pos_;return true;}return false;}
  void literal(std::string_view s){if(input_.substr(pos_,s.size())!=s)fail("literal");pos_+=s.size();}
  static void utf8(std::string& out,std::uint32_t cp){if(cp<=0x7f)out.push_back(static_cast<char>(cp));else if(cp<=0x7ff){out.push_back(static_cast<char>(0xc0|(cp>>6)));out.push_back(static_cast<char>(0x80|(cp&0x3f)));}else if(cp<=0xffff){out.push_back(static_cast<char>(0xe0|(cp>>12)));out.push_back(static_cast<char>(0x80|((cp>>6)&0x3f)));out.push_back(static_cast<char>(0x80|(cp&0x3f)));}else if(cp<=0x10ffff){out.push_back(static_cast<char>(0xf0|(cp>>18)));out.push_back(static_cast<char>(0x80|((cp>>12)&0x3f)));out.push_back(static_cast<char>(0x80|((cp>>6)&0x3f)));out.push_back(static_cast<char>(0x80|(cp&0x3f)));}else throw error("json_unicode_range");}
  std::uint32_t hex4(){std::uint32_t v=0;for(int n=0;n<4;++n){char c=take();v<<=4;if(c>='0'&&c<='9')v|=c-'0';else if(c>='a'&&c<='f')v|=10+c-'a';else if(c>='A'&&c<='F')v|=10+c-'A';else fail("unicode_hex");}return v;}
  std::string string(){if(take()!='"')fail("string_start");std::string out;while(true){unsigned char c=static_cast<unsigned char>(take());if(c=='"')break;if(c<0x20)fail("string_control");if(c!='\\'){out.push_back(static_cast<char>(c));continue;}char e=take();switch(e){case '"':out.push_back('"');break;case '\\':out.push_back('\\');break;case '/':out.push_back('/');break;case 'b':out.push_back('\b');break;case 'f':out.push_back('\f');break;case 'n':out.push_back('\n');break;case 'r':out.push_back('\r');break;case 't':out.push_back('\t');break;case 'u':{auto cp=hex4();if(cp>=0xd800&&cp<=0xdbff){if(take()!='\\'||take()!='u')fail("surrogate");auto low=hex4();if(low<0xdc00||low>0xdfff)fail("surrogate_low");cp=0x10000+((cp-0xd800)<<10)+(low-0xdc00);}else if(cp>=0xdc00&&cp<=0xdfff)fail("surrogate_low");utf8(out,cp);break;}default:fail("escape");}}return out;}
  value integer(){std::size_t start=pos_;consume('-');if(consume('0')){if(pos_<input_.size()&&std::isdigit(static_cast<unsigned char>(input_[pos_])))fail("leading_zero");}else{if(pos_>=input_.size()||input_[pos_]<'1'||input_[pos_]>'9')fail("integer");while(pos_<input_.size()&&std::isdigit(static_cast<unsigned char>(input_[pos_])))++pos_;}if(pos_<input_.size()&&(input_[pos_]=='.'||input_[pos_]=='e'||input_[pos_]=='E'))fail("non_integer_number");std::string s(input_.substr(start,pos_-start));char* end=nullptr;errno=0;long long n=std::strtoll(s.c_str(),&end,10);if(errno||end!=s.c_str()+s.size())fail("integer_range");return value(static_cast<std::int64_t>(n));}
  value::array array(std::size_t depth){take();value::array a;skip();if(consume(']'))return a;while(true){a.push_back(parse_value(depth));skip();if(consume(']'))return a;if(!consume(','))fail("array_separator");skip();}}
  value::object object(std::size_t depth){take();value::object o;skip();if(consume('}'))return o;while(true){if(pos_>=input_.size()||input_[pos_]!='"')fail("object_key");auto k=string();skip();if(!consume(':'))fail("object_colon");skip();auto [_,ok]=o.emplace(std::move(k),parse_value(depth));if(!ok)fail("duplicate_key");skip();if(consume('}'))return o;if(!consume(','))fail("object_separator");skip();}}
  value parse_value(std::size_t depth){if(depth>max_depth)fail("depth");skip();if(pos_>=input_.size())fail("eof");switch(input_[pos_]){case 'n':literal("null");return value(nullptr);case 't':literal("true");return value(true);case 'f':literal("false");return value(false);case '"':return value(string());case '[':return value(array(depth+1));case '{':return value(object(depth+1));default:if(input_[pos_]=='-'||std::isdigit(static_cast<unsigned char>(input_[pos_])))return integer();fail("token");}}
};

inline void escape(std::string& out,std::string_view s){static constexpr char h[]="0123456789abcdef";out.push_back('"');for(unsigned char c:s){switch(c){case '"':out+="\\\"";break;case '\\':out+="\\\\";break;case '\b':out+="\\b";break;case '\f':out+="\\f";break;case '\n':out+="\\n";break;case '\r':out+="\\r";break;case '\t':out+="\\t";break;default:if(c<0x20){out+="\\u00";out.push_back(h[c>>4]);out.push_back(h[c&15]);}else out.push_back(static_cast<char>(c));}}out.push_back('"');}
inline void emit(std::string& out,const value& v){if(v.is_null()){out+="null";}else if(v.is_bool()){out+=v.as_bool()?"true":"false";}else if(v.is_int()){out+=std::to_string(v.as_int());}else if(v.is_string()){escape(out,v.as_string());}else if(v.is_array()){out.push_back('[');bool first=true;for(const auto& x:v.as_array()){if(!first)out.push_back(',');first=false;emit(out,x);}out.push_back(']');}else{out.push_back('{');bool first=true;for(const auto& [k,x]:v.as_object()){if(!first)out.push_back(',');first=false;escape(out,k);out.push_back(':');emit(out,x);}out.push_back('}');}}
inline value parse(std::string_view s){return parser(s).parse();}
inline std::string canonical(const value& v){std::string out;emit(out,v);return out;}
inline std::string required_string(const value::object& o,std::string_view k){auto i=o.find(k);if(i==o.end()||!i->second.is_string()||i->second.as_string().empty())throw error("json_required_string:"+std::string(k));return i->second.as_string();}
inline std::int64_t required_int(const value::object& o,std::string_view k){auto i=o.find(k);if(i==o.end()||!i->second.is_int())throw error("json_required_int:"+std::string(k));return i->second.as_int();}
inline bool required_bool(const value::object& o,std::string_view k){auto i=o.find(k);if(i==o.end()||!i->second.is_bool())throw error("json_required_bool:"+std::string(k));return i->second.as_bool();}
inline const value::object& required_object(const value::object& o,std::string_view k){auto i=o.find(k);if(i==o.end()||!i->second.is_object())throw error("json_required_object:"+std::string(k));return i->second.as_object();}
inline const value::array& required_array(const value::object& o,std::string_view k){auto i=o.find(k);if(i==o.end()||!i->second.is_array())throw error("json_required_array:"+std::string(k));return i->second.as_array();}

} // namespace kristin::p1a::json
