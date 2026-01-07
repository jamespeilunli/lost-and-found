<script>
  let images = [];
  let error = '';
  let selectedFile = null;
  let timeInput = '';
  let locationInput = '';

  function handleFileSelect(event) {
    const file = event.target.files[0];
    
    if (!file) {
      return;
    }

    // Check if file is an image
    if (!file.type.startsWith('image/')) {
      error = 'Please upload an image file';
      selectedFile = null;
      return;
    }

    error = '';
    selectedFile = file;
  }

  function handleUpload() {
    if (!selectedFile) {
      error = 'Please select an image file';
      return;
    }

    if (!timeInput.trim()) {
      error = 'Please enter the date and time';
      return;
    }

    if (!locationInput.trim()) {
      error = 'Please enter the location';
      return;
    }

    error = '';

    const reader = new FileReader();
    
    reader.onload = (e) => {
      const imageData = {
        id: Date.now(),
        imageUrl: e.target.result,
        fileName: selectedFile.name,
        time: timeInput.trim(),
        location: locationInput.trim()
      };

      images = [...images, imageData];
      
      // Reset form
      selectedFile = null;
      timeInput = '';
      locationInput = '';
      document.getElementById('file-upload').value = '';
    };

    reader.onerror = () => {
      error = 'Error reading image file';
    };

    reader.readAsDataURL(selectedFile);
  }

  function removeImage(id) {
    images = images.filter(img => img.id !== id);
  }

  function clearAll() {
    images = [];
    selectedFile = null;
    timeInput = '';
    locationInput = '';
    error = '';
    document.getElementById('file-upload').value = '';
  }
</script>

<main>
  <div class="container">
    <h1>Image Gallery with Metadata</h1>
    
    <div class="upload-section">
      <div class="upload-form">
        <label for="file-upload" class="file-label">
          <svg 
            xmlns="http://www.w3.org/2000/svg" 
            width="20" 
            height="20" 
            viewBox="0 0 24 24" 
            fill="none" 
            stroke="currentColor" 
            stroke-width="2" 
            stroke-linecap="round" 
            stroke-linejoin="round"
          >
            <rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect>
            <circle cx="8.5" cy="8.5" r="1.5"></circle>
            <polyline points="21 15 16 10 5 21"></polyline>
          </svg>
          {selectedFile ? selectedFile.name : 'Select Image'}
        </label>
        <input
          id="file-upload"
          type="file"
          accept="image/*"
          on:change={handleFileSelect}
          style="display: none;"
        />

        <div class="form-group">
          <label for="time-input">Time *</label>
          <input
            id="time-input"
            type="text"
            class="form-input"
            placeholder="e.g., 2:30 PM, January 15, 2024"
            bind:value={timeInput}
          />
        </div>

        <div class="form-group">
          <label for="location-input">Location *</label>
          <input
            id="location-input"
            type="text"
            class="form-input"
            placeholder="e.g., New York, NY"
            bind:value={locationInput}
          />
        </div>

        <div class="form-actions">
          <button 
            class="upload-button" 
            on:click={handleUpload}
            disabled={!selectedFile || !timeInput.trim() || !locationInput.trim()}
          >
            Upload Image
          </button>
          {#if images.length > 0}
            <button class="clear-button" on:click={clearAll}>
              Clear All
            </button>
          {/if}
        </div>
      </div>
    </div>

    {#if error}
      <div class="error-message">{error}</div>
    {/if}

    {#if images.length > 0}
      <div class="gallery-section">
        <div class="gallery-header">
          <h2>Uploaded Images ({images.length})</h2>
        </div>
        <div class="image-list">
          {#each images as image (image.id)}
            <div class="image-card">
              <div class="image-container">
                <img src={image.imageUrl} alt={image.fileName} />
                <button 
                  class="delete-button" 
                  on:click={() => removeImage(image.id)}
                  aria-label="Delete image"
                >
                  ×
                </button>
              </div>
              <div class="image-info">
                <div class="info-row">
                  <span class="info-label">Time:</span>
                  <span class="info-value">{image.time}</span>
                </div>
                <div class="info-row">
                  <span class="info-label">Location:</span>
                  <span class="info-value">{image.location}</span>
                </div>
                <div class="info-row">
                  <span class="info-label">File:</span>
                  <span class="info-value filename">{image.fileName}</span>
                </div>
              </div>
            </div>
          {/each}
        </div>
      </div>
    {:else}
      <div class="empty-state">
        <p>No images uploaded yet. Select an image and add time and location 
           to get started.</p>
      </div>
    {/if}
  </div>
</main>

<style>
  :global(body) {
    margin: 0;
    padding: 0;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 
                 Oxygen, Ubuntu, Cantarell, sans-serif;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    min-height: 100vh;
    padding: 2rem 0;
  }

  main {
    width: 100%;
    max-width: 1200px;
    margin: 0 auto;
    padding: 0 2rem;
  }

  .container {
    background: white;
    border-radius: 16px;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.3);
    padding: 2.5rem;
  }

  h1 {
    margin: 0 0 2rem 0;
    color: #333;
    font-size: 2rem;
    text-align: center;
    font-weight: 600;
  }

  .upload-section {
    margin-bottom: 2rem;
  }

  .upload-form {
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
  }

  .file-label {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 0.5rem;
    padding: 1rem;
    background: #f9fafb;
    border: 2px dashed #d1d5db;
    border-radius: 8px;
    cursor: pointer;
    font-size: 1rem;
    color: #374151;
    transition: all 0.2s;
  }

  .file-label:hover {
    background: #f3f4f6;
    border-color: #667eea;
  }

  .form-group {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .form-group label {
    font-weight: 500;
    color: #374151;
    font-size: 0.9rem;
  }

  .form-input {
    padding: 0.75rem;
    border: 2px solid #e5e7eb;
    border-radius: 8px;
    font-size: 1rem;
    transition: border-color 0.2s;
    box-sizing: border-box;
  }

  .form-input:focus {
    outline: none;
    border-color: #667eea;
  }

  .form-actions {
    display: flex;
    gap: 1rem;
  }

  .upload-button {
    flex: 1;
    padding: 0.75rem 1.5rem;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    border: none;
    border-radius: 8px;
    cursor: pointer;
    font-size: 1rem;
    font-weight: 500;
    transition: transform 0.2s, box-shadow 0.2s, opacity 0.2s;
  }

  .upload-button:hover:not(:disabled) {
    transform: translateY(-2px);
    box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
  }

  .upload-button:disabled {
    opacity: 0.5;
    cursor: not-allowed;
    transform: none;
  }

  .clear-button {
    padding: 0.75rem 1.5rem;
    background: #f3f4f6;
    color: #374151;
    border: 1px solid #d1d5db;
    border-radius: 8px;
    cursor: pointer;
    font-size: 1rem;
    font-weight: 500;
    transition: background 0.2s;
  }

  .clear-button:hover {
    background: #e5e7eb;
  }

  .error-message {
    padding: 1rem;
    background: #fee2e2;
    color: #dc2626;
    border-radius: 8px;
    margin-bottom: 1.5rem;
    border: 1px solid #fecaca;
  }

  .gallery-section {
    margin-top: 2rem;
  }

  .gallery-header {
    margin-bottom: 1.5rem;
  }

  .gallery-header h2 {
    margin: 0;
    color: #333;
    font-size: 1.5rem;
    font-weight: 600;
  }

  .image-list {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 1.5rem;
  }

  .image-card {
    background: #f9fafb;
    border-radius: 12px;
    overflow: hidden;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
    transition: transform 0.2s, box-shadow 0.2s;
  }

  .image-card:hover {
    transform: translateY(-4px);
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.15);
  }

  .image-container {
    position: relative;
    width: 100%;
    padding-top: 75%;
    background: #e5e7eb;
    overflow: hidden;
  }

  .image-container img {
    position: absolute;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    object-fit: cover;
  }

  .delete-button {
    position: absolute;
    top: 0.5rem;
    right: 0.5rem;
    width: 32px;
    height: 32px;
    background: rgba(220, 38, 38, 0.9);
    color: white;
    border: none;
    border-radius: 50%;
    cursor: pointer;
    font-size: 1.5rem;
    line-height: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    transition: background 0.2s, transform 0.2s;
  }

  .delete-button:hover {
    background: rgba(220, 38, 38, 1);
    transform: scale(1.1);
  }

  .image-info {
    padding: 1rem;
  }

  .info-row {
    display: flex;
    gap: 0.5rem;
    margin-bottom: 0.75rem;
    align-items: flex-start;
  }

  .info-row:last-child {
    margin-bottom: 0;
  }

  .info-label {
    font-weight: 600;
    color: #6b7280;
    font-size: 0.875rem;
    min-width: 70px;
  }

  .info-value {
    color: #374151;
    font-size: 0.875rem;
    flex: 1;
    word-break: break-word;
  }

  .info-value.filename {
    font-family: 'Monaco', 'Menlo', 'Ubuntu Mono', monospace;
    font-size: 0.8rem;
    color: #6b7280;
  }

  .empty-state {
    text-align: center;
    padding: 3rem;
    color: #9ca3af;
    font-style: italic;
  }

  @media (max-width: 640px) {
    main {
      padding: 0 1rem;
    }

    .container {
      padding: 1.5rem;
    }

    h1 {
      font-size: 1.5rem;
    }

    .form-actions {
      flex-direction: column;
    }

    .upload-button,
    .clear-button {
      width: 100%;
    }

    .image-list {
      grid-template-columns: 1fr;
    }
  }
</style>
