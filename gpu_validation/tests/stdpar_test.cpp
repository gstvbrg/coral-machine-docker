#include <algorithm>
#include <execution>
#include <numeric>
#include <vector>

int main() {
    constexpr std::size_t kSize = 100'000'000;
    std::vector<float> data(kSize, 1.0f);

    std::transform(std::execution::par,
                   data.begin(), data.end(), data.begin(),
                   [](float x) { return x * 2.0f; });

    float sum = std::reduce(std::execution::par,
                            data.begin(), data.end(), 0.0f);

    return sum > 0.f ? 0 : 1;
}
