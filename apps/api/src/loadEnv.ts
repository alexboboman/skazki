// Local development: read .env from the working directory when it exists.
// Variables that are already set in the real environment win over the file.
try {
  process.loadEnvFile();
} catch {
  // no .env file: the environment is configured another way
}
