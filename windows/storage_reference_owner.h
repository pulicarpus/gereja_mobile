#pragma once
#include <memory>
#include <utility>

// Create the owner before starting an SDK request. Copying a StorageReference
// after starting a request creates a different SDK internal reference and does
// not preserve the one used by the in-flight request.
template <typename Reference>
std::shared_ptr<Reference> gkii_storage_reference(Reference reference) {
  return std::make_shared<Reference>(std::move(reference));
}
