#!/bin/bash
for model in $(ollama list | awk 'NR>1 {print $1}'); do
  echo "Updating context for $model..."

  # Export existing modelfile and update/append num_ctx
  ollama show "$model" --modelfile | grep -v 'PARAMETER num_ctx' > /tmp/temp_modelfile
  echo "PARAMETER num_ctx 65536" >> /tmp/temp_modelfile

  # Re-create model with same name
  ollama create "$model" -f /tmp/temp_modelfile
done
rm /tmp/temp_modelfile