#include <cstddef>
#include <Processing.NDI.Lib.h>

#include <iostream>
#include <cstring>
#include <vector>
#include <string>
#include <fstream>
#include <cstdio>
#include <cstdlib>
#include <regex>

struct AudioDevice {
    std::string label;
    std::string alsa_device;
    bool recommended = false;
};

struct Config {
    std::string source_name;
    std::string audio_device;
};

static Config g_config;

std::string trim_quotes(const std::string& s) {
    if (s.size() >= 2 && s.front() == '"' && s.back() == '"') {
        return s.substr(1, s.size() - 2);
    }
    return s;
}

Config load_config() {
    Config cfg;
    std::ifstream config("/etc/ndiplayer.conf");
    if (!config.is_open()) {
        return cfg;
    }

    std::string line;
    while (std::getline(config, line)) {
        if (line.rfind("SOURCE_NAME=", 0) == 0) {
            cfg.source_name = trim_quotes(line.substr(std::string("SOURCE_NAME=").size()));
        } else if (line.rfind("AUDIO_DEVICE=", 0) == 0) {
            cfg.audio_device = trim_quotes(line.substr(std::string("AUDIO_DEVICE=").size()));
        }
    }

    return cfg;
}

bool save_config(const Config& cfg) {
    std::ofstream config("/etc/ndiplayer.conf");
    if (!config.is_open()) {
        return false;
    }

    config << "SOURCE_NAME=\"" << cfg.source_name << "\"\n";
    config << "AUDIO_DEVICE=\"" << cfg.audio_device << "\"\n";
    return true;
}

std::vector<std::string> find_ndi_sources() {
    std::vector<std::string> result;

    if (!NDIlib_initialize()) {
        std::cerr << "Falha ao inicializar NDI.\n";
        return result;
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
        return result;
    }

    std::cout << "\nProcurando sources NDI...\n";

    uint32_t last_count = 0;
    int stable_rounds = 0;
    std::vector<NDIlib_source_t> discovered_sources;

    while (true) {
        NDIlib_find_wait_for_sources(finder, 2000);

        uint32_t count = 0;
        const NDIlib_source_t* sources = NDIlib_find_get_current_sources(finder, &count);

        if (count != last_count) {
            std::cout << "Sources encontradas agora: " << count << "\n";
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

        if (!discovered_sources.empty() && stable_rounds >= 3) {
            break;
        }
    }

    for (const auto& src : discovered_sources) {
        result.push_back(src.p_ndi_name ? src.p_ndi_name : "(sem nome)");
    }

    NDIlib_find_destroy(finder);
    NDIlib_destroy();
    return result;
}

std::vector<AudioDevice> list_audio_devices() {
    std::vector<AudioDevice> devices;

    FILE* fp = popen("aplay -l", "r");
    if (!fp) {
        return devices;
    }

    char line[1024];
    std::regex re(R"(card ([0-9]+): ([^ ]+) \[(.*?)\], device ([0-9]+): (.*?) \[(.*?)\])");

    int hdmi_count = 0;

    while (fgets(line, sizeof(line), fp)) {
        std::string s(line);
        while (!s.empty() && (s.back() == '\n' || s.back() == '\r')) {
            s.pop_back();
        }

        std::smatch m;
        if (std::regex_search(s, m, re)) {
            int card = std::stoi(m[1].str());
            std::string card_name = m[2].str();
            int dev = std::stoi(m[4].str());
            std::string dev_name = m[5].str();
            std::string desc = m[6].str();

            AudioDevice d;
            d.alsa_device = "plughw:" + std::to_string(card) + "," + std::to_string(dev);

            if (dev_name.find("HDMI") != std::string::npos || desc.find("HDMI") != std::string::npos) {
                hdmi_count++;
                d.label = "HDMI " + std::to_string(hdmi_count);
                if (desc.find('*') != std::string::npos) {
                    d.label += " (Recomendado - normalmente e a saida ativa)";
                    d.recommended = true;
                }
            } else if (desc.find("Analog") != std::string::npos) {
                d.label = "Analogico (P2)";
            } else if (desc.find("Digital") != std::string::npos || desc.find("SPDIF") != std::string::npos) {
                d.label = "SPDIF Digital";
            } else {
                d.label = card_name + " / " + dev_name;
            }

            devices.push_back(d);
        }
    }

    pclose(fp);
    return devices;
}

void show_current_config(const Config& cfg) {
    std::cout << "\n========================================\n";
    std::cout << "         CONFIGURACAO ATUAL\n";
    std::cout << "========================================\n";
    std::cout << "Source NDI : " << (cfg.source_name.empty() ? "(nao definida)" : cfg.source_name) << "\n";
    std::cout << "Audio ALSA : " << (cfg.audio_device.empty() ? "(nao definido)" : cfg.audio_device) << "\n";
}

void select_source() {
    auto sources = find_ndi_sources();

    if (sources.empty()) {
        std::cout << "\nNenhuma source NDI encontrada.\n";
        return;
    }

    std::cout << "\nSources NDI encontradas:\n";
    for (size_t i = 0; i < sources.size(); ++i) {
        std::cout << "[" << i + 1 << "] " << sources[i] << "\n";
    }

    int choice = 0;
    while (true) {
        std::cout << "\nEscolha a source NDI: ";
        std::cin >> choice;

        if (std::cin.fail()) {
            std::cin.clear();
            std::cin.ignore(10000, '\n');
            std::cout << "Entrada invalida.\n";
            continue;
        }

        if (choice < 1 || choice > (int)sources.size()) {
            std::cout << "Numero fora da faixa.\n";
            continue;
        }

        break;
    }

    g_config.source_name = sources[choice - 1];
    std::cout << "\nSource selecionada: " << g_config.source_name << "\n";
}

void select_audio() {
    auto devices = list_audio_devices();

    if (devices.empty()) {
        std::cout << "\nNenhuma saida de audio encontrada.\n";
        return;
    }

    std::cout << "\nSaidas de audio detectadas:\n";
    for (size_t i = 0; i < devices.size(); ++i) {
        std::cout << "[" << i + 1 << "] " << devices[i].label << "\n";
    }

    int recommended_index = -1;
    for (size_t i = 0; i < devices.size(); ++i) {
        if (devices[i].recommended) {
            recommended_index = (int)i;
            break;
        }
    }

    if (recommended_index >= 0) {
        std::cout << "\nDica: a opcao [" << (recommended_index + 1)
                  << "] costuma ser a saida HDMI ativa.\n";
    }

    int choice = 0;
    while (true) {
        std::cout << "\nEscolha a saida de audio: ";
        std::cin >> choice;

        if (std::cin.fail()) {
            std::cin.clear();
            std::cin.ignore(10000, '\n');
            std::cout << "Entrada invalida.\n";
            continue;
        }

        if (choice < 1 || choice > (int)devices.size()) {
            std::cout << "Numero fora da faixa.\n";
            continue;
        }

        break;
    }

    g_config.audio_device = devices[choice - 1].alsa_device;
    std::cout << "\nSaida de audio selecionada: " << devices[choice - 1].label
              << " -> " << g_config.audio_device << "\n";
}

int main() {
    g_config = load_config();

    while (true) {
        std::cout << "\n========================================\n";
        std::cout << "           NDI PLAYER SETUP\n";
        std::cout << "========================================\n";
        std::cout << "1 - Selecionar source NDI\n";
        std::cout << "2 - Selecionar saida de audio\n";
        std::cout << "3 - Mostrar configuracao atual\n";
        std::cout << "4 - Salvar e sair\n";
        std::cout << "0 - Cancelar\n";
        std::cout << "\nEscolha uma opcao: ";

        int option = -1;
        std::cin >> option;

        if (std::cin.fail()) {
            std::cin.clear();
            std::cin.ignore(10000, '\n');
            std::cout << "Entrada invalida.\n";
            continue;
        }

        if (option == 1) {
            select_source();
        } else if (option == 2) {
            select_audio();
        } else if (option == 3) {
            show_current_config(g_config);
        } else if (option == 4) {
            if (g_config.source_name.empty()) {
                std::cout << "\nDefina a source NDI antes de salvar.\n";
                continue;
            }
            if (g_config.audio_device.empty()) {
                std::cout << "\nDefina a saida de audio antes de salvar.\n";
                continue;
            }

            if (!save_config(g_config)) {
                std::cout << "\nFalha ao salvar em /etc/ndiplayer.conf\n";
                std::cout << "Execute este programa com sudo.\n";
                return 1;
            }

            std::cout << "\nConfiguracao salva com sucesso em /etc/ndiplayer.conf\n";
            return 0;
        } else if (option == 0) {
            std::cout << "\nCancelado.\n";
            return 0;
        } else {
            std::cout << "Opcao invalida.\n";
        }
    }
}
