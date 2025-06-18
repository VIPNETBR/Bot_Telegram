#!/bin/bash

set -e

echo "==== Instalador Bot Telegram SSH + Mercado Pago ===="

read -p "Ingresa tu TELEGRAM BOT TOKEN: " BOT_TOKEN
read -p "Ingresa tu MERCADO PAGO ACCESS TOKEN: " MP_TOKEN
read -p "Ingresa el dominio (registro tipo A vinculado al IP): " DOMINIO

echo "Configura los planes (deja vacío para valores por defecto)"

read -p "Plan 1 - Duración días [default 31]: " PLAN1_DIAS
PLAN1_DIAS=${PLAN1_DIAS:-31}
read -p "Plan 1 - Precio (ej: 20): " PLAN1_PRECIO
PLAN1_PRECIO=${PLAN1_PRECIO:-20}

read -p "Plan 2 - Duración días [default 16]: " PLAN2_DIAS
PLAN2_DIAS=${PLAN2_DIAS:-16}
read -p "Plan 2 - Precio (ej: 15): " PLAN2_PRECIO
PLAN2_PRECIO=${PLAN2_PRECIO:-15}

read -p "Plan 3 - Duración días [default 8]: " PLAN3_DIAS
PLAN3_DIAS=${PLAN3_DIAS:-8}
read -p "Plan 3 - Precio (ej: 10): " PLAN3_PRECIO
PLAN3_PRECIO=${PLAN3_PRECIO:-10}

echo ""
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

echo "⚙️ Guardando configuración..."

cat > config.py <<EOF
TELEGRAM_BOT_TOKEN="${BOT_TOKEN}"
MERCADO_PAGO_ACCESS_TOKEN="${MP_TOKEN}"
DOMINIO="${DOMINIO}"
EOF

cat > plans.json <<EOF
[
  {"dias": ${PLAN1_DIAS}, "precio": ${PLAN1_PRECIO}},
  {"dias": ${PLAN2_DIAS}, "precio": ${PLAN2_PRECIO}},
  {"dias": ${PLAN3_DIAS}, "precio": ${PLAN3_PRECIO}}
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
        f"✅ PAGAMENTO GERADO COM SUCESSO\n\n"
        f"PIX COPIA E COLA:\n{copia_cola}\n\n"
        f"URL DO TICKET:\n{link}"
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
                    "🧩ACCESO CREADO CON EXITO ✅\n\n"
                    f"👤USUARIO: {acceso['user']}\n"
                    f"🔐CONTRASEÑA: {acceso['pass']}\n"
                    f"📲LIMITE: {acceso.get('limit', 1)}\n"
                    f"🗓️VENCIMIENTO: {vencimiento}\n\n"
                    "📥 APLICACION: https://play.google.com/store/apps/details?id=app.conecta.pro"
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
                f.write(f"{datetime.datetime.now()} - Pago aprobado: Usuario {acceso['user'] if acceso else 'No disponible'}, Dias {dias}\n")

    return "OK", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
EOF

cat > menu.sh <<'EOF'
#!/bin/bash
source ~/bot_ssh/venv/bin/activate
cd ~/bot_ssh

clear
echo "===== Logs de ventas recientes ====="
tail -n 50 webhook.log
read -p "Presiona Enter para continuar al menú..."

while true; do
    clear
    echo "===== Menú de Administración Bot SSH ====="
    echo "1) Iniciar Bot Telegram"
    echo "2) Detener Bot Telegram"
    echo "3) Iniciar Webhook"
    echo "4) Detener Webhook"
    echo "5) Ver estado (procesos)"
    echo "6) Editar planes"
    echo "7) Ver ventas (logs de webhook)"
    echo "8) Desinstalar todo"
    echo "9) Salir"
    echo "=========================================="
    read -p "Elige opción: " opt

    case $opt in
        1)
            pkill -f bot.py || true
            nohup python3 bot.py > bot.log 2>&1 &
            echo "Bot iniciado."
            sleep 2
            ;;
        2)
            pkill -f bot.py && echo "Bot detenido." || echo "Bot no estaba corriendo."
            sleep 2
            ;;
        3)
            pkill -f webhook.py || true
            nohup python3 webhook.py > webhook.log 2>&1 &
            echo "Webhook iniciado."
            sleep 2
            ;;
        4)
            pkill -f webhook.py && echo "Webhook detenido." || echo "Webhook no estaba corriendo."
            sleep 2
            ;;
        5)
            echo "Procesos bot y webhook:"
            pgrep -fl bot.py
            pgrep -fl webhook.py
            read -p "Enter para continuar..."
            ;;
        6)
            nano plans.json
            ;;
        7)
            echo "Logs webhook:"
            tail -n 50 webhook.log
            read -p "Enter para continuar..."
            ;;
        8)
            read -p "¿Seguro quieres desinstalar todo? (s/n): " yn
            if [[ "$yn" == "s" ]]; then
                pkill -f bot.py || true
                pkill -f webhook.py || true
                rm -rf ~/bot_ssh
                echo "Desinstalado."
                exit 0
            fi
            ;;
        9)
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
echo "⚠️ Recuerda abrir el puerto 5000 para el webhook y puerto 80 si planeas usarlo."
echo "Si el puerto 80 está ocupado, usa el 5000."
echo ""
echo "Nota: El dominio que ingresaste debe apuntar a esta IP para que el webhook funcione correctamente."
