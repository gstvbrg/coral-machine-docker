#include <palabos3D.h>
#include <palabos3D.hh>

using namespace plb;
using namespace plb::descriptors;

namespace {
constexpr plint nx = 100;
constexpr plint ny = 100;
constexpr plint nz = 100;
constexpr int iterations = 100;
constexpr double omega = 1.0;  // Relaxation parameter for BGK dynamics
}

int main(int argc, char* argv[]) {
    plbInit(&argc, &argv);

    MultiBlockLattice3D<double, D3Q19Descriptor> lattice(
        nx, ny, nz,
        new AcceleratedBGKdynamics<double, D3Q19Descriptor>(omega));

    // Warm up lattice to ensure GPU memory allocations happen
    lattice.initialize();

    for (int i = 0; i < iterations; ++i) {
        lattice.collideAndStream();
    }

    return 0;
}
