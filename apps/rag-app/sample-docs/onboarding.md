# Onboarding a New RAG App

The golden path for a new RAG application is the Backstage template called "Create RAG App".
The template asks for the app name, the owning team, the chat model and the vector store size.
It opens a pull request that adds a folder under gitops/apps in the aiforge-platform repository.

After the pull request is merged, the Argo CD ApplicationSet named "rag-apps" deploys the app automatically.
A new app is usually live in under 10 minutes.

Every app runs in its own Kubernetes namespace that is named after the app.
The namespace is labelled with the team name, which is how OpenCost shows the infrastructure cost per team.

The vector store for each app is created by the Crossplane VectorStore API.
The default vector dimension is 768, which matches the nomic-embed-text embedding model.
