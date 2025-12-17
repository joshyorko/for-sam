# Sam's RFP AI Agent - Setup Guide

## 📁 Files in This Folder

| File | Description |
|------|-------------|
| `cole_ultimate_rag_v4.json` | **Original** Cole Medin's Ultimate RAG Agent V4 (full version with all features) |
| `sam_rfp_agent_pro.json` | **Custom** RFP Agent for Sam - simplified & focused on RFP Q&A retrieval |

---

## 🚀 Quick Start: Sam's RFP Agent

### 1. Prerequisites

You need these accounts/services:
- **n8n** (self-hosted or cloud)
- **Postgres with PGVector** (Use [Neon](https://neon.tech) free tier or [Supabase](https://supabase.com))
- **OpenAI API Key**
- **Google Drive** (for document storage)
- **Cohere API Key** (optional, for reranking - improves accuracy)

### 2. Import the Workflow

1. Open your n8n instance
2. Go to **Workflows** > **Import from File**
3. Select `sam_rfp_agent_pro.json`

### 3. Configure Credentials

Replace `YOUR_*_CREDENTIAL_ID` placeholders in these nodes:

| Credential Type | Nodes Using It |
|----------------|----------------|
| Postgres | Create Documents Table, Delete Old Vectors, Upsert Document Metadata, PGVector Store, Chat Memory, Log Success/Error |
| Google Drive OAuth2 | File Created Trigger, File Updated Trigger, Download File |
| OpenAI API | Embeddings (Ingest), Embeddings (Retrieve), OpenAI Chat Model (Primary) |
| Cohere API | Reranker Cohere (optional) |
| Anthropic API | Anthropic Claude Fallback (optional) |
| Slack API | Slack Error Alert (optional) |

### 4. Configure Google Drive Folder

1. Create a folder in Google Drive for your RFP documents
2. Copy the folder ID from the URL: `https://drive.google.com/drive/folders/YOUR_FOLDER_ID`
3. Update the `File Created` and `File Updated` trigger nodes with this ID

### 5. Initialize Database

1. **Run the "Create Documents Table" node** (one time only)
2. This creates the `rfp_documents` table for metadata storage
3. The `rfp_vectors` table is auto-created by PGVector on first insert

### 6. Test the Workflow

1. Upload an RFP document to your Google Drive folder
2. Wait for the trigger (runs every minute)
3. Check workflow execution - document should be processed
4. Open the chat interface and ask: "What is your company's approach to data security?"

---

## 🔧 Key Features

### 🛡️ Production Robustness (NEW!)

| Feature | Description |
|---------|-------------|
| **Retry on Failure** | 3 retries with exponential backoff for API calls |
| **Error Logging** | All ingestion successes/failures tracked in `rfp_ingestion_log` table |
| **Slack Alerts** | Optional notifications when ingestion fails |
| **Fallback LLM** | Anthropic Claude backup if OpenAI fails |
| **Input Validation** | Prevents empty/invalid queries (min 3 characters) |
| **Confidence Levels** | Response includes High/Medium/Low confidence for each match |

### Upsert Logic (No Duplicates!)
Unlike Zubair's original "delete all" approach, this uses **smart upsert**:
- When a file is updated, only that file's vectors are deleted
- Then the new version is inserted
- Other documents remain untouched

### RFP-Specific System Prompt
The agent is configured to:
- Return **exact Q&A pairs** from past RFPs
- Include **source document titles**
- Return **multiple matches** when available
- **Never hallucinate** - only uses knowledge base content

### Cohere Reranking
- Fetches 25 results from vector search
- Reranks to top 5 most relevant
- Dramatically improves accuracy for RFP matching

---

## 📊 Comparison: Cole's V4 vs Sam's RFP Agent

| Feature | Cole's V4 | Sam's RFP Agent |
|---------|-----------|-----------------|
| Vector Store | Postgres/PGVector | Postgres/PGVector |
| Document Types | PDF, DOCX, TXT, CSV, Excel | PDF, DOCX, TXT |
| SQL Query Tool | ✅ Yes (for tabular data) | ❌ Removed (not needed for RFPs) |
| File Content Tool | ✅ Yes | ❌ Removed |
| Reranking | ✅ Cohere | ✅ Cohere |
| Agentic Chunking | ✅ LLM-based | ❌ Recursive Character (simpler) |
| Trash Cleanup | ✅ Auto-deletes trashed files | ❌ Not included |
| System Prompt | General RAG | **RFP-specific Q&A retrieval** |
| Complexity | High (50+ nodes) | Medium (25 nodes) |

---

## 🔄 If You Want the Full Cole Version

Import `cole_ultimate_rag_v4.json` instead. It includes:
- Agentic chunking (LLM decides where to split text)
- SQL tool for querying tabular data (CSV/Excel)
- List Documents tool
- Get File Contents tool
- Automatic trash cleanup every 15 minutes
- More file type support

---

## 📚 Resources

- [Cole Medin's YouTube](https://www.youtube.com/@ColeMedin) - Ultimate RAG tutorials
- [Zubair's Original Video](https://youtu.be/OMJ0T85UFFY) - RFP AI Agent tutorial
- [n8n Documentation](https://docs.n8n.io/)
- [Neon Postgres](https://neon.tech) - Free Postgres with PGVector
- [Supabase](https://supabase.com) - Alternative Postgres hosting

---

## 🐛 Troubleshooting

### "Vector table not found"
Run the workflow once with a document to auto-create the `rfp_vectors` table.

### "Embeddings dimension mismatch"
Make sure you're using `text-embedding-3-small` (1536 dimensions) in all embedding nodes.

### "No results returned"
1. Check that documents were actually ingested (look at workflow executions)
2. Try a more specific query
3. Increase `topK` in the PGVector retriever node

### "Cohere API error"
Cohere reranking is optional. If you don't have a Cohere API key, set `useReranker: false` in the PGVector retriever node.
