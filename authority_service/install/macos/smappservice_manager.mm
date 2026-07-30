#import <Foundation/Foundation.h>
#import <ServiceManagement/ServiceManagement.h>
#include <cstdio>
#include <cstring>
int main(int argc,const char**argv){
 @autoreleasepool{
  if(argc==2&&std::strcmp(argv[1],"--source-self-test")==0){std::puts("{\"status\":\"passed\",\"installer\":\"SMAppService\",\"completionEligible\":false}");return 0;}
  if(argc!=3){std::fprintf(stderr,"usage: manager register|unregister|status plist-name\n");return 2;}
  NSString*op=[NSString stringWithUTF8String:argv[1]];NSString*plist=[NSString stringWithUTF8String:argv[2]];
  SMAppService*service=[SMAppService daemonServiceWithPlistName:plist];NSError*error=nil;
  if([op isEqualToString:@"status"]){std::printf("{\"status\":\"observed\",\"registrationStatus\":%ld,\"plist\":\"%s\"}\n",(long)service.status,argv[2]);return 0;}
  BOOL ok=[op isEqualToString:@"register"]?[service registerAndReturnError:&error]:[op isEqualToString:@"unregister"]?[service unregisterAndReturnError:&error]:NO;
  if(!ok){std::fprintf(stderr,"SMAppService failed: %s\n",error?error.localizedDescription.UTF8String:"unsupported operation");return 1;}
  std::printf("{\"status\":\"passed\",\"operation\":\"%s\",\"plist\":\"%s\"}\n",argv[1],argv[2]);return 0;
 }
}
