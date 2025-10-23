import streamlit as st
import requests
import os

st.set_page_config(layout="wide")
st.title("Lokal RAG Asistanı (Apache Dökümanları) 🤖")
st.caption("GPU üzerinde çalışan Qwen modeli ve Qdrant veritabanı ile")

# Backend API adresini Kubernetes servis adından al
BACKEND_URL = os.environ.get(
    "BACKEND_URL", 
    # ArgoCD'nin oluşturduğu servisin tam DNS adı
    "http://rag-backend-service.rag-system.svc.cluster.local:8000"
)

# Sidebar'da Ingest butonu
with st.sidebar:
    st.header("Veri Yönetimi")
    st.markdown("Apache PDF dökümanlarını vektör veritabanına yüklemek için bu butonu kullanın. (Sadece 1 kez gereklidir)")
    if st.button("Veriyi Yükle (Ingest)"):
        with st.spinner("PDF'ler okunuyor, parçalanıyor ve Qdrant'a yükleniyor... Bu işlem zaman alabilir."):
            try:
                response = requests.post(f"{BACKEND_URL}/ingest")
                response.raise_for_status()
                st.success(f"Veri başarıyla yüklendi! Detay: {response.json()}")
            except requests.exceptions.RequestException as e:
                st.error(f"Veri yüklenirken hata oluştu: {e}")
                st.error(f"Backend cevabı: {e.response.text if e.response else 'No response'}")

# Sohbet arayüzü
if "messages" not in st.session_state:
    st.session_state.messages = []

for message in st.session_state.messages:
    with st.chat_message(message["role"]):
        st.markdown(message["content"])

if prompt := st.chat_input("Apache dökümanları hakkında bir soru sorun..."):
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    with st.chat_message("assistant"):
        with st.spinner("Cevap GPU'da üretiliyor..."):
            try:
                response = requests.post(
                    f"{BACKEND_URL}/chat", 
                    json={"query": prompt}
                )
                response.raise_for_status()
                answer = response.json().get("response", "Bir hata oluştu.")
                st.markdown(answer)
                st.session_state.messages.append({"role": "assistant", "content": answer})
            except requests.exceptions.RequestException as e:
                st.error(f"Backend'e bağlanırken hata: {e}")
                st.error(f"Backend cevabı: {e.response.text if e.response else 'No response'}")