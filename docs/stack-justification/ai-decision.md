# AI Stack

## LLM: ibm-granite-4.2

We will use granite-4.2-30B on the cluster for prompt engineering and evaluation, served via vLLM.

We will use granite-4.2-8b for local development, served via Ollama


## Serving Methods: vLLM and Ollama

Ollama - best for local development, quantizes models so they run better on less powerful hardware (e.g. laptops)

vLLM - best for development on the cluster due to its optimization for larger GPUs, like the H100s in the cluster.
