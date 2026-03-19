#include <cstddef>
#include <Processing.NDI.Lib.h>
#include <iostream>
#include <cstring>
#include <vector>
#include <string>

int main() {
    if (!NDIlib_initialize()) {
        std::cerr << "Falha ao inicializar NDI.\n";
        return 1;
    }

    NDIlib_find_create_t find_desc;
    std::memset(&find_desc, 0, sizeof(find_desc));
    find_desc.show_local_sources = true;
    find_desc.p_groups = nullptr;
    find_desc.p_extra_ips = nullptr;

    NDIlib_find_instance_t finder = NDIlib_find_create_v2(&find_desc);
    if (!finder) {
        std::cerr << "Falha ao criar finder NDI.\n";
        NDIlib_destroy();
        return 1;
    }

    uint32_t last_count = 0;
    int stable_rounds = 0;
    std::vector<NDIlib_source_t> discovered_sources;

    while (true) {
        NDIlib_find_wait_for_sources(finder, 2000);

        uint32_t count = 0;
        const NDIlib_source_t* sources = NDIlib_find_get_current_sources(finder, &count);

        if (count != last_count) {
            last_count = count;
            stable_rounds = 0;
        } else {
            stable_rounds++;
        }

        if (count > 0) {
            discovered_sources.clear();
            for (uint32_t i = 0; i < count; ++i) {
                discovered_sources.push_back(sources[i]);
            }
        }

        if (!discovered_sources.empty() && stable_rounds >= 2) {
            break;
        }

        if (stable_rounds >= 3 && discovered_sources.empty()) {
            break;
        }
    }

    for (const auto& src : discovered_sources) {
        std::cout << (src.p_ndi_name ? src.p_ndi_name : "(sem nome)") << "\n";
    }

    NDIlib_find_destroy(finder);
    NDIlib_destroy();
    return 0;
}
