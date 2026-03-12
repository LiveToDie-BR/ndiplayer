#include <cstddef>
#include <Processing.NDI.Lib.h>
#include <SDL2/SDL.h>
#include <alsa/asoundlib.h>

#include <iostream>
#include <cstring>
#include <csignal>
#include <string>
#include <fstream>
#include <thread>
#include <atomic>
#include <algorithm>
#include <vector>
#include <map>

static std::atomic<bool> g_running(true);

struct Config {
    std::string source_name;
    std::string audio_device;
};

void handle_signal(int) {
    g_running = false;
}

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
            std::string value = line.substr(std::string("SOURCE_NAME=").size());
            cfg.source_name = trim_quotes(value);
        } else if (line.rfind("AUDIO_DEVICE=", 0) == 0) {
            std::string value = line.substr(std::string("AUDIO_DEVICE=").size());
            cfg.audio_device = trim_quotes(value);
        }
    }

    return cfg;
}

int16_t float_to_s16(float v) {
    v = std::max(-1.0f, std::min(1.0f, v));
    int sample = static_cast<int>(v * 32767.0f);
    if (sample > 32767) sample = 32767;
    if (sample < -32768) sample = -32768;
    return static_cast<int16_t>(sample);
}

bool open_alsa_device(const std::string& device_name, snd_pcm_t** pcm_handle) {
    int err = snd_pcm_open(pcm_handle, device_name.c_str(), SND_PCM_STREAM_PLAYBACK, 0);
    if (err < 0) {
        std::cerr << "Falha ao abrir ALSA '" << device_name << "': "
                  << snd_strerror(err) << "\n";
        return false;
    }

    err = snd_pcm_set_params(
        *pcm_handle,
        SND_PCM_FORMAT_S16_LE,
        SND_PCM_ACCESS_RW_INTERLEAVED,
        2,
        48000,
        1,
        100000
    );

    if (err < 0) {
        std::cerr << "Falha ao configurar ALSA '" << device_name << "': "
                  << snd_strerror(err) << "\n";
        snd_pcm_close(*pcm_handle);
        *pcm_handle = nullptr;
        return false;
    }

    return true;
}

void audio_thread_func(NDIlib_recv_instance_t receiver, std::string audio_device) {
    snd_pcm_t* pcm_handle = nullptr;

    if (!open_alsa_device(audio_device, &pcm_handle)) {
        std::cerr << "Audio desabilitado por falha no ALSA.\n";
        return;
    }

    std::cout << "Audio ALSA iniciado em: " << audio_device << "\n";

    while (g_running) {
        NDIlib_audio_frame_v3_t audio_frame;
        std::memset(&audio_frame, 0, sizeof(audio_frame));

        NDIlib_frame_type_e type = NDIlib_recv_capture_v3(
            receiver,
            nullptr,
            &audio_frame,
            nullptr,
            1000
        );

        if (type == NDIlib_frame_type_audio) {
            if (!audio_frame.p_data || audio_frame.no_samples <= 0 || audio_frame.no_channels <= 0) {
                NDIlib_recv_free_audio_v3(receiver, &audio_frame);
                continue;
            }

            const int samples = audio_frame.no_samples;
            const int channels = audio_frame.no_channels;
            const int stride_floats = audio_frame.channel_stride_in_bytes / sizeof(float);

            float* base = reinterpret_cast<float*>(audio_frame.p_data);
            std::vector<int16_t> out(samples * 2);

            for (int i = 0; i < samples; ++i) {
                float left = 0.0f;
                float right = 0.0f;

                if (channels == 1) {
                    float mono = base[i];
                    left = mono;
                    right = mono;
                } else {
                    float* ch0 = base + (0 * stride_floats);
                    float* ch1 = base + (1 * stride_floats);
                    left = ch0[i];
                    right = ch1[i];
                }

                out[i * 2 + 0] = float_to_s16(left);
                out[i * 2 + 1] = float_to_s16(right);
            }

            snd_pcm_sframes_t written = snd_pcm_writei(pcm_handle, out.data(), samples);

            if (written < 0) {
                written = snd_pcm_recover(pcm_handle, static_cast<int>(written), 1);
                if (written < 0) {
                    std::cerr << "Erro de audio ALSA: "
                              << snd_strerror(static_cast<int>(written)) << "\n";
                }
            }

            NDIlib_recv_free_audio_v3(receiver, &audio_frame);
        }
        else if (type == NDIlib_frame_type_status_change) {
            std::cout << "Mudanca de status do receiver (audio).\n";
        }
    }

    snd_pcm_drain(pcm_handle);
    snd_pcm_close(pcm_handle);
}

void video_thread_func(NDIlib_recv_instance_t receiver) {
    if (SDL_Init(SDL_INIT_VIDEO) != 0) {
        std::cerr << "Falha ao inicializar SDL: " << SDL_GetError() << "\n";
        g_running = false;
        return;
    }

    SDL_Window* window = nullptr;
    SDL_Renderer* renderer = nullptr;
    SDL_Texture* texture = nullptr;

    int tex_w = 0;
    int tex_h = 0;

    std::cout << "Video SDL iniciado.\n";

    while (g_running) {
        SDL_Event e;
        while (SDL_PollEvent(&e)) {
            if (e.type == SDL_QUIT) g_running = false;
            if (e.type == SDL_KEYDOWN && e.key.keysym.sym == SDLK_ESCAPE) g_running = false;
        }

        NDIlib_video_frame_v2_t video_frame;
        std::memset(&video_frame, 0, sizeof(video_frame));

        NDIlib_frame_type_e type = NDIlib_recv_capture_v3(
            receiver,
            &video_frame,
            nullptr,
            nullptr,
            1000
        );

        if (type == NDIlib_frame_type_video) {
            if (!window) {
                window = SDL_CreateWindow(
                    "NDI Player",
                    SDL_WINDOWPOS_CENTERED,
                    SDL_WINDOWPOS_CENTERED,
                    video_frame.xres,
                    video_frame.yres,
                    SDL_WINDOW_FULLSCREEN_DESKTOP
                );

                if (!window) {
                    std::cerr << "Falha ao criar janela SDL: " << SDL_GetError() << "\n";
                    NDIlib_recv_free_video_v2(receiver, &video_frame);
                    g_running = false;
                    break;
                }

                renderer = SDL_CreateRenderer(
                    window,
                    -1,
                    SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC
                );

                if (!renderer) {
                    std::cerr << "Falha ao criar renderer SDL: " << SDL_GetError() << "\n";
                    NDIlib_recv_free_video_v2(receiver, &video_frame);
                    g_running = false;
                    break;
                }
            }

            if (!texture || tex_w != video_frame.xres || tex_h != video_frame.yres) {
                if (texture) {
                    SDL_DestroyTexture(texture);
                    texture = nullptr;
                }

                tex_w = video_frame.xres;
                tex_h = video_frame.yres;

                texture = SDL_CreateTexture(
                    renderer,
                    SDL_PIXELFORMAT_BGRA32,
                    SDL_TEXTUREACCESS_STREAMING,
                    tex_w,
                    tex_h
                );

                if (!texture) {
                    std::cerr << "Falha ao criar textura SDL: " << SDL_GetError() << "\n";
                    NDIlib_recv_free_video_v2(receiver, &video_frame);
                    g_running = false;
                    break;
                }
            }

            if (video_frame.p_data) {
                if (SDL_UpdateTexture(texture, nullptr, video_frame.p_data,
                                      video_frame.line_stride_in_bytes) != 0) {
                    std::cerr << "Falha em SDL_UpdateTexture: " << SDL_GetError() << "\n";
                    NDIlib_recv_free_video_v2(receiver, &video_frame);
                    g_running = false;
                    break;
                }

                SDL_RenderClear(renderer);
                SDL_RenderCopy(renderer, texture, nullptr, nullptr);
                SDL_RenderPresent(renderer);
            }

            NDIlib_recv_free_video_v2(receiver, &video_frame);
        }
        else if (type == NDIlib_frame_type_status_change) {
            std::cout << "Mudanca de status do receiver (video).\n";
        }
    }

    if (texture) SDL_DestroyTexture(texture);
    if (renderer) SDL_DestroyRenderer(renderer);
    if (window) SDL_DestroyWindow(window);
    SDL_Quit();
}

int main() {
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);

    Config cfg = load_config();

    if (cfg.source_name.empty()) {
        std::cerr << "Falha ao ler SOURCE_NAME de /etc/ndiplayer.conf\n";
        return 1;
    }

    if (cfg.audio_device.empty()) {
        cfg.audio_device = "default";
    }

    std::cout << "Source configurada: " << cfg.source_name << "\n";
    std::cout << "Saida de audio configurada: " << cfg.audio_device << "\n";

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

    std::cout << "Procurando a source configurada...\n";

    NDIlib_source_t selected_source;
    bool found = false;

    while (g_running && !found) {
        NDIlib_find_wait_for_sources(finder, 2000);

        uint32_t count = 0;
        const NDIlib_source_t* sources = NDIlib_find_get_current_sources(finder, &count);

        std::cout << "Sources encontradas: " << count << "\n";

        for (uint32_t i = 0; i < count; ++i) {
            std::string current_name = sources[i].p_ndi_name ? sources[i].p_ndi_name : "";
            std::cout << " - " << current_name << "\n";

            if (current_name == cfg.source_name) {
                selected_source = sources[i];
                found = true;
                break;
            }
        }
    }

    if (!found) {
        std::cerr << "Source configurada nao encontrada.\n";
        NDIlib_find_destroy(finder);
        NDIlib_destroy();
        return 1;
    }

    std::cout << "Conectando em: "
              << (selected_source.p_ndi_name ? selected_source.p_ndi_name : "(sem nome)")
              << "\n";

    NDIlib_recv_create_v3_t recv_desc;
    std::memset(&recv_desc, 0, sizeof(recv_desc));
    recv_desc.source_to_connect_to = selected_source;
    recv_desc.color_format = NDIlib_recv_color_format_BGRX_BGRA;
    recv_desc.bandwidth = NDIlib_recv_bandwidth_highest;
    recv_desc.allow_video_fields = true;
    recv_desc.p_ndi_recv_name = "ndiplayer-v2.2";

    NDIlib_recv_instance_t receiver = NDIlib_recv_create_v3(&recv_desc);
    if (!receiver) {
        std::cerr << "Falha ao criar receiver NDI.\n";
        NDIlib_find_destroy(finder);
        NDIlib_destroy();
        return 1;
    }

    std::thread video_thread(video_thread_func, receiver);
    std::thread audio_thread(audio_thread_func, receiver, cfg.audio_device);

    video_thread.join();
    g_running = false;
    audio_thread.join();

    NDIlib_recv_destroy(receiver);
    NDIlib_find_destroy(finder);
    NDIlib_destroy();

    std::cout << "Encerrado.\n";
    return 0;
}
