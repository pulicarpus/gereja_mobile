#include "storage_reference_owner.h"
#include <functional>
#include <iostream>
#include <stdexcept>

// Model the SDK's reference-specific future registry without contacting a
// backend. Each copied reference owns a distinct registry, as the C++ SDK does.
struct Reference {
  std::shared_ptr<int> registry = std::make_shared<int>(42);
  Reference() = default;
  Reference(const Reference&) : registry(std::make_shared<int>(42)) {}
};

int main() {
  try {
    std::weak_ptr<int> unsafe_registry;
    { Reference temporary; unsafe_registry = temporary.registry; }
    if (!unsafe_registry.expired()) throw std::runtime_error("Unsafe case did not release registry");
    std::weak_ptr<int> pending_registry;
    std::function<void()> delayed;
    {
      auto owner = gkii_storage_reference(Reference{});
      pending_registry = owner->registry;
      delayed = [owner, pending_registry] {
        if (pending_registry.expired() || pending_registry.lock() != owner->registry) {
          throw std::runtime_error("Request's original registry was released");
        }
      };
    }
    if (pending_registry.expired()) throw std::runtime_error("Owner died before delayed completion");
    delayed();
    delayed = nullptr;
    if (!pending_registry.expired()) throw std::runtime_error("Completed request owner leaked");
    // A value capture of a copied SDK reference cannot preserve the original
    // request's registry; it must capture the shared owner instead.
    std::weak_ptr<int> original;
    std::unique_ptr<Reference> copy;
    { Reference ref; original = ref.registry; copy = std::make_unique<Reference>(ref); }
    if (!original.expired() || !copy->registry) throw std::runtime_error("Copy semantics regression");
    std::cout << "Temporary registry loss reproduced; delayed shared-owner completion passed\n";
    return 0;
  } catch (const std::exception& error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
