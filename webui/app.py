from flask import Flask, render_template, request, redirect, url_for, flash
import os
import subprocess
from pathlib import Path

app = Flask(__name__)
app.secret_key = "ndiplayer-local-ui"

CONFIG_PATH = Path("/etc/ndiplayer.conf")
SCAN_BINARY = "/usr/local/bin/ndiplayer-scan-sources"


def run_command(cmd):
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            check=False
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except Exception as e:
        return 1, "", str(e)


def read_config():
    data = {
        "SOURCE_NAME": "",
        "AUDIO_DEVICE": ""
    }

    if not CONFIG_PATH.exists():
        return data

    for line in CONFIG_PATH.read_text().splitlines():
        line = line.strip()
        if line.startswith("SOURCE_NAME="):
            data["SOURCE_NAME"] = line.split("=", 1)[1].strip().strip('"')
        elif line.startswith("AUDIO_DEVICE="):
            data["AUDIO_DEVICE"] = line.split("=", 1)[1].strip().strip('"')

    return data


def write_config(source_name, audio_device):
    content = (
        f'SOURCE_NAME="{source_name}"\n'
        f'AUDIO_DEVICE="{audio_device}"\n'
    )
    CONFIG_PATH.write_text(content)


def get_service_status():
    code, out, err = run_command(["systemctl", "is-active", "ndiplayer.service"])
    if code == 0:
        return out
    return err or "unknown"


def get_audio_devices():
    code, out, err = run_command(["aplay", "-l"])
    devices = []

    if code != 0:
        return devices

    hdmi_count = 0

    for line in out.splitlines():
        line = line.strip()
        if not line.startswith("card "):
            continue

        # exemplo:
        # card 0: HDMI [HDA Intel HDMI], device 3: HDMI 0 [HDMI 0 *]
        try:
            left, right = line.split(", device ", 1)
            card_num = left.split("card ")[1].split(":")[0].strip()
            device_num = right.split(":")[0].strip()
            description = right.split(": ", 1)[1]

            alsa_device = f"plughw:{card_num},{device_num}"

            label = description
            recommended = False

            if "HDMI" in description:
                hdmi_count += 1
                label = f"HDMI {hdmi_count}"
                if "*" in description:
                    label += " (Recomendado - normalmente e a saida ativa)"
                    recommended = True
            elif "Analog" in description:
                label = "Analogico (P2)"
            elif "Digital" in description or "SPDIF" in description:
                label = "SPDIF Digital"

            devices.append({
                "label": label,
                "alsa_device": alsa_device,
                "recommended": recommended,
                "raw": description
            })
        except Exception:
            continue

    return devices


def get_ndi_sources():
    if not os.path.exists(SCAN_BINARY):
        return []

    code, out, err = run_command([SCAN_BINARY])
    if code != 0:
        return []

    sources = [line.strip() for line in out.splitlines() if line.strip()]
    return sources


@app.route("/")
def index():
    config = read_config()
    service_status = get_service_status()
    audio_devices = get_audio_devices()
    ndi_sources = get_ndi_sources()

    return render_template(
        "index.html",
        config=config,
        service_status=service_status,
        audio_devices=audio_devices,
        ndi_sources=ndi_sources
    )


@app.route("/save", methods=["POST"])
def save():
    source_name = request.form.get("source_name", "").strip()
    audio_device = request.form.get("audio_device", "").strip()

    if not source_name:
        flash("Selecione uma source NDI.")
        return redirect(url_for("index"))

    if not audio_device:
        flash("Selecione uma saida de audio.")
        return redirect(url_for("index"))

    try:
        write_config(source_name, audio_device)

        code, out, err = run_command(["systemctl", "restart", "ndiplayer.service"])
        if code == 0:
            flash("Configuracao salva e player reiniciado com sucesso.")
        else:
            flash(f"Configuracao salva, mas houve erro ao reiniciar o player: {err or out}")

    except Exception as e:
        flash(f"Erro ao salvar configuracao: {e}")

    return redirect(url_for("index"))


@app.route("/restart-player", methods=["POST"])
def restart_player():
    code, out, err = run_command(["systemctl", "restart", "ndiplayer.service"])
    if code == 0:
        flash("Servico ndiplayer reiniciado com sucesso.")
    else:
        flash(f"Erro ao reiniciar o servico: {err or out}")
    return redirect(url_for("index"))


@app.route("/stop-player", methods=["POST"])
def stop_player():
    code, out, err = run_command(["systemctl", "stop", "ndiplayer.service"])
    if code == 0:
        flash("Servico ndiplayer parado com sucesso.")
    else:
        flash(f"Erro ao parar o servico: {err or out}")
    return redirect(url_for("index"))


@app.route("/start-player", methods=["POST"])
def start_player():
    code, out, err = run_command(["systemctl", "start", "ndiplayer.service"])
    if code == 0:
        flash("Servico ndiplayer iniciado com sucesso.")
    else:
        flash(f"Erro ao iniciar o servico: {err or out}")
    return redirect(url_for("index"))


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
