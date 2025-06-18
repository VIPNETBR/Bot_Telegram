#!/bin/bash

set -e

echo "==== Instalador Bot SSH con Telegram, Mercado Pago y WhatsApp ===="

echo "📦 Actualizando sistema..."
sudo apt update && sudo apt upgrade -y

echo "🐍 Instalando Python y dependencias..."
sudo apt install -y python3 python3-pip python3-venv git curl nano

echo "📁 Creando entorno y directorios..."
mkdir -p ~/bot_ssh && cd ~/bot_ssh
python3 -m venv venv
source venv/bin/activate

pip install --upgrade pip
pip install aiogram mercadopago qrcode[pil] flask requests

echo "⚙️ Guardando configuración base..."

cat > config.py <<EOF
TELEGRAM_BOT_TOKEN="your_telegram_token_here"
MERCADO_PAGO_ACCESS_TOKEN="your_mercadopago_token_here"
DOMINIO="your_domain_here"
EOF

cat > config_whatsapp.py <<EOF
# Configuración Bot WhatsApp (edita estos valores antes de iniciar el bot)

WHATSAPP_TOKEN="your_whatsapp_token_here"
WHATSAPP_PHONE_ID="your_phone_number_id_here"
VERIFY_TOKEN="your_verify_token_here"
API_URL="https://graph.facebook.com/v15.0"
EOF

cat > plans.json <<EOF
[
  {"dias": 31, "precio": 20},
  {"dias": 16, "precio": 15},
  {"dias": 8, "precio": 10}
]
EOF

cat > entrega.py <<'EOF'
accesos_ssh = [
    {"user": "Gabriel", "pass": "6197", "limit": 1},
    {"user": "user2", "pass": "clave2", "limit": 1}
]

def entregar_acceso():
    if accesos_ssh:
        return accesos_ssh.pop(0)
    return None
EOF

cat > bot.py <<'EOF'
import logging
from aiogram import Bot, Dispatcher, types
import json
import qrcode
import io
import mercadopago
from config import TELEGRAM_BOT_TOKEN, MERCADO_PAGO_ACCESS_TOKEN

logging.basicConfig(level=logging.INFO)
bot = Bot(token=TELEGRAM_BOT_TOKEN)
dp = Dispatcher(bot)
sdk = mercadopago.SDK(MERCADO_PAGO_ACCESS_TOKEN)

with open('plans.json', 'r') as f:
    PLANS = json.load(f)

@dp.message_handler(commands=['start'])
async def start(msg: types.Message):
    keyboard = types.InlineKeyboardMarkup(row_width=1)
    for i, plan in enumerate(PLANS):
        keyboard.add(types.InlineKeyboardButton(
            text=f"{plan['dias']} días - ${plan['precio']}",
            callback_data=f"comprar_{i}"
        ))
    await msg.answer("🔥 *Planes SSH Disponibles:*\n\nElige uno de los siguientes planes:",
                     parse_mode="Markdown", reply_markup=keyboard)

@dp.callback_query_handler(lambda call: call.data.startswith("comprar_"))
async def comprar_callback(call: types.CallbackQuery):
    idx = int(call.data.split("_")[1])
    plan = PLANS[idx]

    payment_data = {
        "transaction_amount": float(plan["precio"]),
        "description": f"SSH {plan['dias']} días",
        "payment_method_id": "pix",
        "payer": {"email": f"user{call.from_user.id}@mail.com"}
    }

    result = sdk.payment().create(payment_data)
    payment = result["response"]
    link = payment["point_of_interaction"]["transaction_data"]["ticket_url"]
    copia_cola = payment["point_of_interaction"]["transaction_data"]["qr_code"]

    qr = qrcode.make(link)
    bio = io.BytesIO()
    qr.save(bio, format='PNG')
    bio.seek(0)

    await call.message.answer_photo(photo=bio, caption="📸 Escanea para pagar via QR PIX (Mercado Pago)")

    texto_pago = (
        f"✅ PAGO GENERADO CON ÉXITO\n\n"
        f"PIX COPIA Y PEGA:\n{copia_cola}\n\n"
        f"URL DEL TICKET:\n{link}"
    )
    await call.message.answer(texto_pago)

@dp.message_handler(commands=['ventas'])
async def ventas(msg: types.Message):
    try:
        with open("webhook.log", "r") as f:
            lines = f.readlines()
        ultimas_ventas = "".join(lines[-50:])
        await msg.answer(f"🧾 Últimas 50 ventas:\n\n{ultimas_ventas}")
    except Exception as e:
        await msg.answer(f"Error leyendo ventas: {e}")

from aiogram import executor
if __name__ == "__main__":
    print("INFO: Bot iniciado")
    executor.start_polling(dp, skip_updates=True)
EOF

cat > webhook.py <<'EOF'
from flask import Flask, request
import mercadopago
import requests
from entrega import entregar_acceso
from config import MERCADO_PAGO_ACCESS_TOKEN, TELEGRAM_BOT_TOKEN
import datetime
import json

app = Flask(__name__)
sdk = mercadopago.SDK(MERCADO_PAGO_ACCESS_TOKEN)

with open('plans.json', 'r') as f:
    PLANS = json.load(f)

@app.route("/webhook", methods=["POST"])
def webhook():
    data = request.get_json()
    if data and "data" in data and "id" in data["data"]:
        payment_id = data["data"]["id"]
        payment = sdk.payment().get(payment_id)["response"]

        if payment["status"] == "approved":
            email = payment["payer"]["email"]
            user_id = email.split("@")[0].replace("user", "")

            descripcion = payment["description"]
            dias = next((p["dias"] for p in PLANS if str(p["dias"]) in descripcion), 7)
            hoy = datetime.datetime.now()
            vencimiento = (hoy + datetime.timedelta(days=dias)).strftime("%d-%m-%Y")

            acceso = entregar_acceso()
            if acceso:
                msg = (
                    "✅ PAGO CONFIRMADO !\n\n"
                    "🧩ACCESO CREADO CON ÉXITO ✅\n\n"
                    f"👤USUARIO: {acceso['user']}\n"
                    f"🔐CONTRASEÑA: {acceso['pass']}\n"
                    f"📲LÍMITE: {acceso.get('limit', 1)}\n"
                    f"🗓️VENCIMIENTO: {vencimiento}\n\n"
                    "📥 APLICACIÓN: https://play.google.com/store/apps/details?id=app.conecta.pro"
                )
            else:
                msg = "⚠️ Pago confirmado pero no hay accesos SSH disponibles."

            url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
            payload = {
                "chat_id": int(user_id),
                "text": msg,
                "parse_mode": "Markdown"
            }
            requests.post(url, json=payload)

            # Guardar log
            with open("webhook.log", "a") as f:
                f.write(f"{datetime.datetime.now()} - Pago aprobado: Usuario {acceso['user'] if acceso else 'No disponible'}, Días {dias}\n")

    return "OK", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

cat > bot_whatsapp.py <<'EOF'
import time
import json
import requests
from flask import Flask, request, jsonify
from config_whatsapp import WHATSAPP_TOKEN, WHATSAPP_PHONE_ID, VERIFY_TOKEN, API_URL

app = Flask(__name__)

def send_message(to, text):
    url = f"{API_URL}/{WHATSAPP_PHONE_ID}/messages"
    headers = {
        "Authorization": f"Bearer {WHATSAPP_TOKEN}",
        "Content-Type": "application/json"
    }
    data = {
        "messaging_product": "whatsapp",
        "to": to,
        "text": {"body": text}
    }
    r = requests.post(url, headers=headers, json=data)
    return r.status_code == 200

@app.route('/webhook', methods=['GET'])
def verify():
    mode = request.args.get('hub.mode')
    token = request.args.get('hub.verify_token')
    challenge = request.args.get('hub.challenge')
    if mode == 'subscribe' and token == VERIFY_TOKEN:
        return challenge
    return 'Error, invalid token', 403

@app.route('/webhook', methods=['POST'])
def webhook():
    data = request.get_json()
    if data and "entry" in data:
        for entry in data["entry"]:
            for change in entry.get("changes", []):
                value = change.get("value", {})
                messages = value.get("messages", [])
                for message in messages:
                    from_number = message["from"]
                    text_body = message.get("text", {}).get("body", "").lower()

                    if "hola" in text_body:
                        send_message(from_number, "¡Hola! Bienvenido al Bot SSH. Escribe '1' para crear un test, '2' para comprar SSH, '3' para renovar, o '4' para descargar la app.")
                    elif text_body == "1":
                        send_message(from_number, "Función de crear test aún no implementada.")
                    elif text_body == "2":
                        send_message(from_number, "Planes disponibles:\n1) 31 días - $20\n2) 16 días - $15\n3) 8 días - $10\nEnvía el número del plan para comprar.")
                    elif text_body in ["1", "2", "3"]:
                        send_message(from_number, "Gracias por elegir un plan. Pronto recibirás el código de pago.")
                    elif text_body == "3":
                        send_message(from_number, "Función de renovación aún no implementada.")
                    elif text_body == "4":
                        send_message(from_number, "Descarga nuestra app aquí:\nhttps://play.google.com/store/apps/details?id=app.conecta.pro")
                    else:
                        send_message(from_number, "No entendí tu mensaje. Escribe 'hola' para comenzar.")
    return jsonify(status="ok")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=6000)
EOF

cat > menu.sh <<'EOF'
#!/bin/bash
source ~/bot_ssh/venv/bin/activate
cd ~/bot_ssh

function check_whatsapp_config() {
    if [ ! -f config_whatsapp.py ]; then
        echo "❌ Archivo config_whatsapp.py no encontrado."
        return 1
    fi
    local content=$(grep -E "WHATSAPP_TOKEN|WHATSAPP_PHONE_ID|VERIFY_TOKEN|API_URL" config_whatsapp.py)
    if echo "$content" | grep -q "your_whatsapp_token_here\|your_phone_number_id_here\|your_verify_token_here\|your_api_url_here"; then
        echo "❌ Configuración de Bot WhatsApp incompleta. Edita config_whatsapp.py antes de iniciar."
        return 1
    fi
    return 0
}

while true; do
    clear
    echo "===== Menú de Administración Bot SSH ====="
    echo "1) Bot Telegram"
    echo "2) Bot WhatsApp"
    echo "3) Ajustes"
    echo "4) Desinstalar script"
    echo "5) Salir"
    echo "=========================================="
    read -p "Elige opción: " opt

    case $opt in
        1)
            while true; do
                clear
                echo "===== Bot Telegram ====="
                echo "1) Activar Bot Telegram"
                echo "2) Desactivar Bot Telegram"
                echo "3) Editar config.py"
                echo "4) Ver ventas"
                echo "5) Volver al menú principal"
                read -p "Elige opción: " topt

                case $topt in
                    1)
                        pkill -f bot.py || true
                        nohup python3 bot.py > bot.log 2>&1 &
                        echo "✅ Bot Telegram iniciado."
                        sleep 3
                        ;;
                    2)
                        pkill -f bot.py && echo "Bot Telegram detenido." || echo "Bot Telegram no estaba corriendo."
                        sleep 3
                        ;;
                    3)
                        nano config.py
                        ;;
                    4)
                        echo "Últimas 50 ventas:"
                        tail -n 50 webhook.log
                        read -p "Presiona Enter para continuar..."
                        ;;
                    5)
                        break
                        ;;
                    *)
                        echo "Opción inválida."
                        sleep 1
                        ;;
                esac
            done
            ;;
        2)
            while true; do
                clear
                echo "===== Bot WhatsApp ====="
                echo "1) Activar Bot WhatsApp"
                echo "2) Desactivar Bot WhatsApp"
                echo "3) Configurar Bot WhatsApp (editar config_whatsapp.py)"
                echo "4) Volver al menú principal"
                read -p "Elige opción: " wopt

                case $wopt in
                    1)
                        check_whatsapp_config
                        if [ $? -eq 0 ]; then
                            pkill -f bot_whatsapp.py || true
                            nohup python3 bot_whatsapp.py > bot_whatsapp.log 2>&1 &
                            echo "✅ Bot WhatsApp iniciado."
                        else
                            echo "⚠️ Corrige la configuración primero."
                        fi
                        sleep 3
                        ;;
                    2)
                        pkill -f bot_whatsapp.py && echo "Bot WhatsApp detenido." || echo "Bot WhatsApp no estaba corriendo."
                        sleep 3
                        ;;
                    3)
                        nano config_whatsapp.py
                        ;;
                    4)
                        break
                        ;;
                    *)
                        echo "Opción inválida."
                        sleep 1
                        ;;
                esac
            done
            ;;
        3)
            echo "Ajustes aún no implementados."
            sleep 2
            ;;
        4)
            read -p "¿Seguro quieres desinstalar todo? (s/n): " yn
            if [[ "$yn" == "s" ]]; then
                pkill -f bot.py || true
                pkill -f webhook.py || true
                pkill -f bot_whatsapp.py || true
                rm -rf ~/bot_ssh
                echo "Desinstalado."
                exit 0
            fi
            ;;
        5)
            exit 0
            ;;
        *)
            echo "Opción inválida."
            sleep 1
            ;;
    esac
done
EOF

chmod +x menu.sh

echo ""
echo "✅ Instalación completada."
echo "👉 Para iniciar el menú de administración:"
echo "   cd ~/bot_ssh"
echo "   source venv/bin/activate"
echo "   ./menu.sh"
echo ""
echo "⚠️ Recuerda abrir los puertos 5000 (webhook), 6000 (bot WhatsApp) y 80 (si usas para web)."
echo "Configura los tokens en config.py y config_whatsapp.py antes de iniciar los bots."
