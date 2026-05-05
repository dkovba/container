// fix-bugs: 2026-05-02 04:47 — 0 critical, 2 high, 0 medium, 0 low (2 total)
//===----------------------------------------------------------------------===//
// Copyright © 2025-2026 Apple Inc. and the container project authors.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//   https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//===----------------------------------------------------------------------===//

// Flagged #1 (1 of 2): HIGH: `AuditToken.h` lacks include guards, causing redeclaration errors on multiple inclusion
// The header had no `#ifndef`/`#define`/`#endif` include guard (nor `#pragma once`). Any translation unit that includes this header more than once — directly or transitively — would encounter a duplicate declaration of `xpc_dictionary_get_audit_token`, resulting in a compile-time error.
#ifndef AuditToken_h
#define AuditToken_h

#include <xpc/xpc.h>
#include <bsm/libbsm.h> 

// Flagged #2 (1 of 2): HIGH: `AuditToken.h` function declaration lacks C linkage, causing link failure in C++ translation units
// The declaration of `xpc_dictionary_get_audit_token` appeared outside any `extern "C"` block. When this header is included in a C++ translation unit, the compiler applies C++ name mangling to the symbol. The XPC library exports the function with C linkage (unmangled), so the linker cannot resolve the mangled reference, producing an undefined-symbol error.
__BEGIN_DECLS
void xpc_dictionary_get_audit_token(xpc_object_t xdict, audit_token_t *token);
// Flagged #2 (2 of 2)
__END_DECLS
// Flagged #1 (2 of 2)
#endif
