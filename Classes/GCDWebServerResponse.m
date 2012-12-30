// Copyright 2012 Pierre-Olivier Latour
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#import <sys/stat.h>

#import "GCDWebServer.h"
#import "Extensions_Foundation.h"
#import "Logging.h"

@implementation GCDWebServerResponse

@synthesize contentType=_type, contentLength=_length, statusCode=_status, cacheControlMaxAge=_maxAge, additionalHeaders=_headers;

+ (GCDWebServerResponse*) response {
  return [[[[self class] alloc] init] autorelease];
}

- (id) init {
  return [self initWithContentType:nil contentLength:0];
}

- (id) initWithContentType:(NSString*)type contentLength:(NSUInteger)length {
  if ((self = [super init])) {
    _type = [type copy];
    _length = length;
    _status = 200;
    _maxAge = 0;
    _headers = [[NSMutableDictionary alloc] init];
    
    if ((_length > 0) && (_type == nil)) {
      _type = [kGCDWebServerDefaultMimeType copy];
    }
  }
  return self;
}

- (void) dealloc {
  [_type release];
  [_headers release];
  
  [super dealloc];
}

- (void) setValue:(NSString*)value forAdditionalHeader:(NSString*)header {
  [_headers setValue:value forKey:header];
}

- (BOOL) hasBody {
  return _type ? YES : NO;
}

@end

@implementation GCDWebServerResponse (Subclassing)

- (BOOL) open {
  [self doesNotRecognizeSelector:_cmd];
  return NO;
}

- (NSInteger) read:(void*)buffer maxLength:(NSUInteger)length {
  [self doesNotRecognizeSelector:_cmd];
  return -1;
}

- (BOOL) close {
  [self doesNotRecognizeSelector:_cmd];
  return NO;
}

@end

@implementation GCDWebServerResponse (Extensions)

+ (GCDWebServerResponse*) responseWithStatusCode:(NSInteger)statusCode {
  return [[[self alloc] initWithStatusCode:statusCode] autorelease];
}

+ (GCDWebServerResponse*) responseWithRedirect:(NSURL*)location permanent:(BOOL)permanent {
  return [[[self alloc] initWithRedirect:location permanent:permanent] autorelease];
}

- (id) initWithStatusCode:(NSInteger)statusCode {
  if ((self = [self initWithContentType:nil contentLength:0])) {
    self.statusCode = statusCode;
  }
  return self;
}

- (id) initWithRedirect:(NSURL*)location permanent:(BOOL)permanent {
  if ((self = [self initWithContentType:nil contentLength:0])) {
    self.statusCode = permanent ? 301 : 307;
    [self setValue:[location absoluteString] forAdditionalHeader:@"Location"];
  }
  return self;
}

@end

@implementation GCDWebServerDataResponse

+ (GCDWebServerDataResponse*) responseWithData:(NSData*)data contentType:(NSString*)type {
  return [[[[self class] alloc] initWithData:data contentType:type] autorelease];
}

- (id) initWithData:(NSData*)data contentType:(NSString*)type {
  if (data == nil) {
    DNOT_REACHED();
    [self release];
    return nil;
  }
  
  if ((self = [super initWithContentType:type contentLength:data.length])) {
    _data = [data retain];
    _offset = -1;
  }
  return self;
}

- (void) dealloc {
  DCHECK(_offset < 0);
  [_data release];
  
  [super dealloc];
}

- (BOOL) open {
  DCHECK(_offset < 0);
  _offset = 0;
  return YES;
}

- (NSInteger) read:(void*)buffer maxLength:(NSUInteger)length {
  DCHECK(_offset >= 0);
  NSInteger size = 0;
  if (_offset < _data.length) {
    size = MIN(_data.length - _offset, length);
    bcopy((char*)_data.bytes + _offset, buffer, size);
    _offset += size;
  }
  return size;
}

- (BOOL) close {
  DCHECK(_offset >= 0);
  _offset = -1;
  return YES;
}

@end

@implementation GCDWebServerDataResponse (Extensions)

+ (GCDWebServerDataResponse*) responseWithText:(NSString*)text {
  return [[[self alloc] initWithText:text] autorelease];
}

+ (GCDWebServerDataResponse*) responseWithHTML:(NSString*)html {
  return [[[self alloc] initWithHTML:html] autorelease];
}

+ (GCDWebServerDataResponse*) responseWithHTMLTemplate:(NSString*)path variables:(NSDictionary*)variables {
  return [[[self alloc] initWithHTMLTemplate:path variables:variables] autorelease];
}

- (id) initWithText:(NSString*)text {
  NSData* data = [text dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) {
    DNOT_REACHED();
    [self release];
    return nil;
  }
  return [self initWithData:data contentType:@"text/plain; charset=utf-8"];
}

- (id) initWithHTML:(NSString*)html {
  NSData* data = [html dataUsingEncoding:NSUTF8StringEncoding];
  if (data == nil) {
    DNOT_REACHED();
    [self release];
    return nil;
  }
  return [self initWithData:data contentType:@"text/html; charset=utf-8"];
}

- (id) initWithHTMLTemplate:(NSString*)path variables:(NSDictionary*)variables {
  NSMutableString* html = [[NSMutableString alloc] initWithContentsOfFile:path encoding:NSUTF8StringEncoding error:NULL];
  [variables enumerateKeysAndObjectsUsingBlock:^(NSString* key, NSString* value, BOOL* stop) {
    [html replaceOccurrencesOfString:[NSString stringWithFormat:@"%%%@%%", key] withString:value options:0 range:NSMakeRange(0, html.length)];
  }];
  id response = [self initWithHTML:html];
  [html release];
  return response;
}

@end

@implementation GCDWebServerFileResponse

+ (GCDWebServerFileResponse*) responseWithFile:(NSString*)path {
  return [[[[self class] alloc] initWithFile:path] autorelease];
}

+ (GCDWebServerFileResponse*) responseWithFile:(NSString*)path isAttachment:(BOOL)attachment {
  return [[[[self class] alloc] initWithFile:path isAttachment:attachment] autorelease];
}

- (id) initWithFile:(NSString*)path {
  return [self initWithFile:path isAttachment:NO];
}

- (id) initWithFile:(NSString*)path isAttachment:(BOOL)attachment {
  struct stat info;
  if (lstat([path fileSystemRepresentation], &info) || !(info.st_mode & S_IFREG)) {
    DNOT_REACHED();
    [self release];
    return nil;
  }
  NSString* type = [[NSFileManager defaultManager] mimeTypeFromPathExtension:[path pathExtension]];
  if (type == nil) {
    type = kGCDWebServerDefaultMimeType;
  }
  
  if ((self = [super initWithContentType:type contentLength:info.st_size])) {
    _path = [path copy];
    if (attachment) {
      NSString* filename = [[path lastPathComponent] convertToEncoding:kHTTPHeaderStringEncoding];  // TODO: Use http://tools.ietf.org/html/rfc5987
      [self setValue:[NSString stringWithFormat:@"attachment; filename=\"%@\"", filename] forAdditionalHeader:@"Content-Disposition"];
    }
  }
  return self;
}

- (void) dealloc {
  DCHECK(_file <= 0);
  [_path release];
  
  [super dealloc];
}

- (BOOL) open {
  DCHECK(_file <= 0);
  _file = open([_path fileSystemRepresentation], O_NOFOLLOW | O_RDONLY);
  return (_file > 0 ? YES : NO);
}

- (NSInteger) read:(void*)buffer maxLength:(NSUInteger)length {
  DCHECK(_file > 0);
  return read(_file, buffer, length);
}

- (BOOL) close {
  DCHECK(_file > 0);
  int result = close(_file);
  _file = 0;
  return (result == 0 ? YES : NO);
}

@end