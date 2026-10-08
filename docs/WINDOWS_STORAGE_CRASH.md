# Windows save/upload access violation

## Latest matching dump: document-reference decoding

`gereja_mobile.exe.5960.dmp` and its supplied executable have matching RSDS
identifiers. This later crash is `0xe06d7363` (`std::logic_error`), with the
Firestore message that settings cannot be changed after the client starts.
The caller at executable RVA `0x36a56` obtains the default Firestore instance
and unconditionally calls its settings setter. This matches the separate
`DATA_TYPE_FIRESTORE_INSTANCE` path in FlutterFire's `firestore_codec.cpp`.
The earlier guard covered `cloud_firestore_plugin.cpp` but missed this codec.

Pigeon cached instances under `appName-databaseUrl`; the codec searched only
`appName`, ignored the database name and attempted to configure the same live
SDK instance again. It also inserted a second owning `unique_ptr`. The patch
now shares a database-aware key between both paths, returns the cached instance
before settings assignment, respects named databases and treats an empty
database identifier as `(default)`. Both remaining setters are guarded.

The Windows regression links the actual patched FlutterFire plugin and decodes
the wire format for instances and document references after starting the SDK
client. It checks default/named database identity, empty-default aliases,
unchanged settings and exactly one owner per database. It uses a fake local
project with a closed loopback host and disabled network. It does not perform
an authenticated photo save; that still needs testing on the user's computer.

## Earlier access violation

The later `gereja_mobile.exe.6700.dmp` records `0xc0000005`, reading address
`0x8`, at executable RVA `0x65e904`. Captured instructions identify Firebase's
`Mutex::Acquire` with a null owner. The stack includes RVA `0x8a919a`. Matching
the SDK archive's instruction patterns and the earlier supplied executable
points to Storage's `AsyncSendRequestWithRetry<Metadata>` querying a released
reference-specific future registry. The new executable/PDB has not been supplied;
this is instruction-pattern correlation, not an exact PDB-symbol stack trace.

Firebase Storage's desktop SDK dispatches retries with the internal reference's
`this` pointer. Destroying a `StorageReference` unregisters its future registry.
FlutterFire 12.4.10 creates temporary references for asynchronous upload,
metadata, URL, delete and download requests. `Sleep(1)` does not keep those
references alive until the asynchronous work finishes.

The Windows-only patch now retains each upload/download stream's reference in
its handler. The other asynchronous operations create shared owners before
starting requests, then capture that same owner through completion. Capturing a
copied SDK reference afterwards would preserve a different internal registry.
The three stream handlers also own their event sinks by value, replacing rvalue
reference members bound to destroyed temporaries.

CMake compiles a patched build-local copy of the plugin and fails if the expected
upstream layout changes. The installed pub cache, Android uploads, storage
permissions, credentials and destinations are unchanged.

The native lifetime regression models the SDK's distinct per-reference registry
and delayed completion, without making backend requests. It checks registry
loss with temporary references, preservation through delayed callbacks, eventual
release and the distinction between a value copy and the same shared owner.
The release build also compiles the actual patched FlutterFire source. These
checks do not constitute an authenticated upload on the affected computer;
profile/gallery saves there still need retesting.
