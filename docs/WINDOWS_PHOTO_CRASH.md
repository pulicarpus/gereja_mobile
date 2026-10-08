# Windows photo crash investigation

The supplied `gereja_mobile.exe.1920.dmp` records an uncaught C++ exception
`0xe06d7363`, rather than the earlier unsupported BMI2 instruction. Its stack
includes executable RVAs `0xc1619`, `0x9162f`, `0x8ae6d` and `0x36936`.
The supplied executable contains the corresponding Firestore settings assignment
and the diagnostic: "Firestore instance has already been started and its settings
can no longer be changed." The throw descriptor identifies `std::logic_error`.

The executable and dump have different PDB identifiers. These matching code
locations support the diagnosis, but this is not an exact-symbol stack trace.
No uploaded executables, dumps or user memory are committed to the repository.

FlutterFire Windows unconditionally assigns settings when populating its native
instance cache. Firebase's underlying instance may already be running; its SDK
rejects even identical assignments. The guard compares the requested settings
with the existing SDK settings before assigning them. Actual configuration
changes retain the SDK's original validation. Authentication, permissions and
upload destinations remain unchanged.

CMake compiles a patched build-local copy of the plugin source. It never changes
the pub cache and fails if the expected upstream assignment changes.

The Windows native regression uses a dummy project, disabled persistence and
network, and a closed loopback endpoint. It reproduces the SDK exception after
starting the client, verifies that repeated identical settings no longer throw,
and checks that different settings are still rejected. CI also runs the existing
Flutter tests, native codec test, release build and startup smoke check.

Real profile/gallery uploads on the affected computer still require retesting;
the regression does not authenticate or write to production services.
