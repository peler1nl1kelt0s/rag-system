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
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Configure logging
log_level = os.environ.get("DEBUG_MODE", "false").lower() == "true"
logging.basicConfig(level=logging.DEBUG if log_level else logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Ubuntu RAG Pipeline API",
    description="Apache dökümanları için RAG API (K3s + GPU)"
)

# Environment variables from .env file
QDRANT_URL = os.environ.get("QDRANT_URL", "http://qdrant-service.rag-system.svc.cluster.local:6333")
OLLAMA_URL = os.environ.get("OLLAMA_URL", "http://ollama-service.rag-system.svc.cluster.local:11434")
DATA_PATH = os.environ.get("DATA_PATH", "/data/")
COLLECTION_NAME = os.environ.get("COLLECTION_NAME", "apache_docs")
MODEL_NAME = os.environ.get("MODEL_NAME", "qwen")

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

# Startup'ta otomatik ingest (opsiyonel)
@app.on_event("startup")
async def startup_event():
    """Uygulama başladığında otomatik PDF yükleme"""
    try:
        logger.info("Startup: Otomatik PDF yükleme kontrol ediliyor...")
        # PDF dosyası var mı kontrol et
        import glob
        pdf_files = glob.glob(f"{DATA_PATH}**/*.pdf", recursive=True)
        if pdf_files:
            logger.info(f"PDF dosyaları bulundu: {pdf_files}")
            # Her zaman yeniden ingest yap (force_recreate=True)
            logger.info("PDF dosyaları bulundu, otomatik ingest başlatılıyor...")
            await ingest_data()
        else:
            logger.info("PDF dosyası bulunamadı, otomatik ingest atlanıyor.")
    except Exception as e:
        logger.error(f"Startup ingest hatası: {e}")

class ChatRequest(BaseModel):
    query: str

@app.post("/chat")
async def chat(request: ChatRequest):
    """
    Kullanıcıdan bir sorgu alır, Qdrant'ta arar ve LLM'e cevaplatır.
    """
    try:
        if not qdrant_client:
            return {"error": "Qdrant veritabanı hazır değil. Lütfen önce /ingest yapın."}

        logger.info(f"Sorgu alındı: {request.query}")
        
        # 1. Qdrant'ta benzerlik ara
        try:
            similar_docs = qdrant_client.similarity_search(request.query, k=5)
            if not similar_docs:
                return {"error": "İlgili döküman bulunamadı. Lütfen farklı bir soru deneyin."}
            
            context = "\n\n".join([doc.page_content for doc in similar_docs])
            logger.info(f"{len(similar_docs)} döküman bulundu")
        except Exception as e:
            logger.error(f"Qdrant arama hatası: {e}")
            return {"error": f"Veritabanında arama yaparken hata oluştu: {e}"}
        
        # 2. Prompt'u oluştur
        prompt_template = f"""
You are an AI assistant that answers questions based on the provided documents.

Your task:
1. Carefully analyze the information in the given context
2. Provide the most accurate and detailed answer to the user's question
3. Base your answer strictly on the context provided
4. If there is insufficient information in the context, clearly state that

Context (from uploaded documents):
{context}

User Question: {request.query}

Please answer the question using the context above. Your answer should be clear, concise, and based solely on the provided information:
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
            
    except Exception as e:
        logger.error(f"Genel chat hatası: {e}")
        return {"error": f"Beklenmeyen hata oluştu: {e}"}

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
        # Daha büyük chunk'lar kullan (fonksiyon tanımları için)
        text_splitter = RecursiveCharacterTextSplitter(
            chunk_size=2000, 
            chunk_overlap=300,
            separators=["\n\n", "\n", ". ", " ", ""]
        )
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