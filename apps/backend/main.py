import uvicorn
import os
from fastapi import FastAPI
from pydantic import BaseModel
from langchain_community.vectorstores import Qdrant
from langchain_community.embeddings import OllamaEmbeddings
from langchain_community.llms import Ollama
from langchain_community.document_loaders import PyPDFLoader, DirectoryLoader
from langchain_text_splitters import RecursiveCharacterTextSplitter
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Lokal RAG Pipeline API",
    description="Apache dökümanları için RAG API"
)

# Kubernetes servis adreslerini kullan (ortam değişkenlerinden almak daha iyidir)
QDRANT_URL = os.environ.get("QDRANT_URL", "http://qdrant-service.rag-system.svc.cluster.local:6333")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://ollama-service.rag-system.svc.cluster.local:11434")

# PDF'lerin Docker imajı içinde kopyalandığı yer
DATA_PATH = "/data/"
COLLECTION_NAME = "apache_docs"
MODEL_NAME = "qwen" # GPU'da çalışacak model

# Global olarak modelleri ve veritabanı bağlantısını başlat
try:
    logger.info(f"Ollama modeline bağlanılıyor: {OLLAMA_URL}")
    embeddings = OllamaEmbeddings(model=MODEL_NAME, base_url=OLLAMA_URL)
    llm = Ollama(model=MODEL_NAME, base_url=OLLAMA_URL)
    
    logger.info(f"Qdrant veritabanına bağlanılıyor: {QDRANT_URL}")
    # İlk başta koleksiyon olmayabilir, /ingest çağrısında oluşturulacak
    qdrant_client = None
    logger.info("Model bağlantıları hazır. Qdrant koleksiyonu /ingest ile oluşturulacak.")

except Exception as e:
    logger.error(f"Başlangıçta hata oluştu: {e}")
    qdrant_client = None # Hata durumunda None ata

class ChatRequest(BaseModel):
    query: str

@app.post("/chat")
async def chat(request: ChatRequest):
    """
    Kullanıcıdan bir sorgu alır, Qdrant'ta arar ve LLM'e cevaplatır.
    """
    if not qdrant_client:
        return {"error": "Qdrant veritabanı hazır değil. Lütfen önce /ingest yapın."}

    logger.info(f"Sorgu alındı: {request.query}")
    
    # 1. Qdrant'ta benzerlik ara
    similar_docs = qdrant_client.similarity_search(request.query, k=3)
    context = "\n".join([doc.page_content for doc in similar_docs])
    
    # 2. Prompt'u oluştur
    prompt_template = f"""
    Sana verilen bağlamı (context) kullanarak soruya cevap ver. Eğer cevap bağlamda yoksa, 'Bilmiyorum' de.
    Bağlam: {context}
    Soru: {request.query}
    Cevap:
    """
    
    # 3. LLM'i (Ollama) çağır
    logger.info("LLM'e cevap ürettiriliyor...")
    try:
        response = llm.invoke(prompt_template)
        logger.info("Cevap alındı.")
        return {"response": response}
    except Exception as e:
        logger.error(f"LLM hatası: {e}")
        return {"error": f"LLM'e bağlanırken hata oluştu: {e}"}

@app.post("/ingest")
async def ingest_data():
    """
    /data/ klasöründeki PDF'leri okur, parçalar, vektöre dönüştürür ve Qdrant'a yükler.
    Bu işlem uzun sürebilir ve sadece bir kez çağrılmalıdır.
    """
    try:
        logger.info(f"Veri yükleme işlemi başlıyor. Kaynak: {DATA_PATH}")
        loader = DirectoryLoader(DATA_PATH, glob="**/*.pdf", loader_cls=PyPDFLoader, show_progress=True)
        documents = loader.load()
        
        if not documents:
            logger.warning("Yüklenecek PDF dökümanı bulunamadı.")
            return {"status": "Yüklenecek PDF dökümanı bulunamadı."}

        logger.info(f"{len(documents)} döküman yüklendi. Parçalanıyor...")
        text_splitter = RecursiveCharacterTextSplitter(chunk_size=1000, chunk_overlap=200)
        texts = text_splitter.split_documents(documents)
        
        logger.info(f"{len(texts)} parça (chunk) oluşturuldu. Vektör veritabanına yükleniyor...")
        
        # Qdrant'a yükle
        Qdrant.from_documents(
            texts,
            embeddings,
            url=QDRANT_URL,
            collection_name=COLLECTION_NAME,
            force_recreate=True, # Her seferinde koleksiyonu yeniden oluştur (veya mevcutsa update et)
        )
        
        # Global istemciyi başlat
        global qdrant_client
        from qdrant_client import QdrantClient
        client = QdrantClient(url=QDRANT_URL)
        qdrant_client = Qdrant(
            client=client,
            collection_name=COLLECTION_NAME,
            embeddings=embeddings
        )
        
        logger.info("Veri başarıyla yüklendi ve Qdrant'a aktarıldı.")
        return {"status": "Veri başarıyla yüklendi.", "chunks": len(texts)}
    except Exception as e:
        logger.error(f"Veri yükleme hatası: {e}")
        return {"error": f"Veri yükleme sırasında hata oluştu: {e}"}

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8000)