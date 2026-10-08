# Windows save/upload access violation

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
