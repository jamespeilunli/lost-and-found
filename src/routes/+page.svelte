<script lang="ts">
  let images: Array<{
    id: number;
    imageUrl: string;
    fileName: string;
    time: string;
    location: string;
  }> = [];
  let error = '';
  let selectedFile: File | null = null;
  let timeInput = '';
  let locationInput = '';

  function handleFileSelect(event: Event) {
    const target = event.target as HTMLInputElement;
    const file = target.files?.[0];
    
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
      error = 'Please enter the time';
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
        imageUrl: e.target?.result as string,
        fileName: selectedFile!.name,
        time: timeInput.trim(),
        location: locationInput.trim()
      };

      images = [...images, imageData];
      
      // Reset form
      selectedFile = null;
      timeInput = '';
      locationInput = '';
      const fileInput = document.getElementById('file-upload') as HTMLInputElement;
      if (fileInput) fileInput.value = '';
    };

    reader.onerror = () => {
      error = 'Error reading image file';
    };

    reader.readAsDataURL(selectedFile);
  }

  function removeImage(id: number) {
    images = images.filter(img => img.id !== id);
  }

  function clearAll() {
    images = [];
    selectedFile = null;
    timeInput = '';
    locationInput = '';
    error = '';
    const fileInput = document.getElementById('file-upload') as HTMLInputElement;
    if (fileInput) fileInput.value = '';
  }
</script>

<svelte:head>
  <title>Lost and Found</title>
  <meta name="description" content="Upload images with time and location metadata" />
</svelte:head>

<div class="min-h-screen bg-gradient-to-br from-indigo-500 via-purple-500 to-pink-500 py-8 px-4">
  <div class="max-w-6xl mx-auto">
    <div class="bg-white rounded-2xl shadow-2xl p-6 md:p-10">
      <h1 class="text-3xl md:text-4xl font-bold text-center text-gray-800 mb-8">
        Lost and Found
      </h1>
      
      <div class="mb-8">
        <div class="space-y-5">
          <label 
            for="file-upload" 
            class="flex items-center justify-center gap-2 p-4 bg-gray-50 border-2 border-dashed border-gray-300 rounded-lg cursor-pointer hover:bg-gray-100 hover:border-indigo-500 transition-colors"
          >
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
              class="text-gray-600"
            >
              <rect x="3" y="3" width="18" height="18" rx="2" ry="2"></rect>
              <circle cx="8.5" cy="8.5" r="1.5"></circle>
              <polyline points="21 15 16 10 5 21"></polyline>
            </svg>
            <span class="text-gray-700">
              {selectedFile ? selectedFile.name : 'Select Image'}
            </span>
          </label>
          <input
            id="file-upload"
            type="file"
            accept="image/*"
            on:change={handleFileSelect}
            class="hidden"
          />

          <div class="space-y-2">
            <label for="time-input" class="block text-sm font-medium text-gray-700">
              Time *
            </label>
            <input
              id="time-input"
              type="text"
              class="w-full px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500 transition-colors"
              placeholder="e.g., 2:30 PM, January 15, 2024"
              bind:value={timeInput}
            />
          </div>

          <div class="space-y-2">
            <label for="location-input" class="block text-sm font-medium text-gray-700">
              Location *
            </label>
            <input
              id="location-input"
              type="text"
              class="w-full px-3 py-2 border-2 border-gray-200 rounded-lg focus:outline-none focus:border-indigo-500 transition-colors"
              placeholder="e.g., New York, NY"
              bind:value={locationInput}
            />
          </div>

          <div class="flex gap-4">
            <button 
              class="flex-1 px-6 py-3 bg-gradient-to-r from-indigo-500 to-purple-600 text-white rounded-lg font-medium hover:from-indigo-600 hover:to-purple-700 disabled:opacity-50 disabled:cursor-not-allowed transition-all transform hover:-translate-y-0.5 hover:shadow-lg disabled:transform-none"
              on:click={handleUpload}
              disabled={!selectedFile || !timeInput.trim() || !locationInput.trim()}
            >
              Upload Image
            </button>
            {#if images.length > 0}
              <button 
                class="px-6 py-3 bg-gray-100 text-gray-700 border border-gray-300 rounded-lg font-medium hover:bg-gray-200 transition-colors"
                on:click={clearAll}
              >
                Clear All
              </button>
            {/if}
          </div>
        </div>
      </div>

      {#if error}
        <div class="mb-6 p-4 bg-red-50 border border-red-200 text-red-700 rounded-lg">
          {error}
        </div>
      {/if}

      {#if images.length > 0}
        <div class="mt-8">
          <h2 class="text-2xl font-bold text-gray-800 mb-6">
            Uploaded Images ({images.length})
          </h2>
          <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
            {#each images as image (image.id)}
              <div class="bg-gray-50 rounded-xl overflow-hidden shadow-md hover:shadow-xl transition-all transform hover:-translate-y-1">
                <div class="relative w-full pb-[75%] bg-gray-200 overflow-hidden">
                  <img 
                    src={image.imageUrl} 
                    alt={image.fileName}
                    class="absolute top-0 left-0 w-full h-full object-cover"
                  />
                  <button 
                    class="absolute top-2 right-2 w-8 h-8 bg-red-600 text-white rounded-full flex items-center justify-center text-xl leading-none hover:bg-red-700 hover:scale-110 transition-all"
                    on:click={() => removeImage(image.id)}
                    aria-label="Delete image"
                  >
                    ×
                  </button>
                </div>
                <div class="p-4 space-y-3">
                  <div class="flex gap-2">
                    <span class="text-sm font-semibold text-gray-500 min-w-[70px]">
                      Time:
                    </span>
                    <span class="text-sm text-gray-700 flex-1 break-words">
                      {image.time}
                    </span>
                  </div>
                  <div class="flex gap-2">
                    <span class="text-sm font-semibold text-gray-500 min-w-[70px]">
                      Location:
                    </span>
                    <span class="text-sm text-gray-700 flex-1 break-words">
                      {image.location}
                    </span>
                  </div>
                  <div class="flex gap-2">
                    <span class="text-sm font-semibold text-gray-500 min-w-[70px]">
                      File:
                    </span>
                    <span class="text-sm text-gray-500 flex-1 break-words font-mono text-xs">
                      {image.fileName}
                    </span>
                  </div>
                </div>
              </div>
            {/each}
          </div>
        </div>
      {:else}
        <div class="text-center py-12 text-gray-500 italic">
          <p>No images uploaded yet. Select an image and add time and location to get started.</p>
        </div>
      {/if}
    </div>
  </div>
</div>
