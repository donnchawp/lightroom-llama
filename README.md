<h1 align="center">
  <img src="./screenshot.png" width=400>
  <br/>
  Lightroom Llama
</h1>

<h4 align="center">Generate metadata for your photos with ollama, directly in Lightroom</h4>
<p align="center">
  <a href="#key-features">Key Features</a> •
  <a href="#how-to-use">How To Use</a> •
  <a href="#features">Features</a> •
  <a href="#credits">Credits</a> •
  <a href="#related">Related</a> •
  <a href="#license">License</a>
</p>

## Key Features

- **AI-Powered Metadata Generation**: Generate titles, captions, and keywords for your photos using local AI models
- **Batch Processing**: Process multiple photos at once with progress tracking
- **Visual Interface**: Preview photos and edit generated content before saving
- **Smart Keyword Organization**: Automatically organizes generated keywords under an "llm" parent keyword
- **Reset Functionality**: Easily remove generated metadata when needed
- **Local Processing**: No internet required - your photos stay on your computer
- **Custom Prompts**: Use your own prompts or leverage the built-in system prompts

## Features

### Single Photo Processing
- Generate metadata for individual photos with a visual interface
- Preview the photo thumbnail while editing
- Customize prompts to get specific results
- Option to use existing title/caption as a starting point
- Real-time status updates during generation

### Batch Processing
- Process multiple selected photos simultaneously
- Progress tracking with detailed status updates
- Configurable settings for batch operations
- Error handling with retry mechanisms
- Efficient processing with optimized API calls

### Reset Metadata
- Remove generated titles and captions
- Clean up LLM-generated keywords (removes only keywords under "llm" parent)
- Selective reset options - choose what to remove
- Safe operation with confirmation dialogs

### Advanced Options
- **System Prompts**: Use sophisticated AI prompts for better results
- **Current Data Integration**: Build upon existing metadata
- **Keyword Management**: Automatic organization under "llm" keyword hierarchy
- **Custom Prompts**: Write your own prompts for specific use cases

## How To Use

### Installation

1. Clone or download the latest version of Lightroom Llama from [here](https://github.com/thejoltjoker/lightroom-llama).
2. Open Adobe Lightroom Classic
3. Go to File > Plug-in Manager
4. Click the "Add" button in the bottom left
5. Navigate to the downloaded plugin folder and select the `lightroom-llama.lrplugin` file
6. Click "Done" to close the Plug-in Manager

### Prerequisites

- Adobe Lightroom Classic
- [Ollama](https://ollama.ai/) installed and running on your computer
- An LLM model downloaded in Ollama (default: minicpm-v)

### Ollama Setup
1. Open a terminal
2. Install [Homebrew](https://brew.sh/) if you don't have it already
   1. `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"`
3. `brew install ollama`
4. `ollama run minicpm-v`

For latest instructions on how to install and run Ollama, see [here](https://github.com/ollama/ollama).

### Using the Plugin

#### Single Photo Processing
1. Select a photo in Lightroom
2. Go to Library > Plug-in Extras > Lightroom Llama...
3. The plugin will show a dialog with the photo thumbnail and metadata fields
4. Customize your prompt or use the default
5. Click "Generate" to create metadata
6. Review and edit the generated content
7. Click "Save" to apply the metadata to your photo

#### Batch Processing
1. Select multiple photos in Lightroom
2. Go to Library > Plug-in Extras > Batch Process with Llama...
3. Configure your batch settings
4. Click "Start Processing" to begin batch generation
5. Monitor progress in the status window
6. Review results and save changes

#### Reset Metadata
1. Select photos with generated metadata
2. Go to Library > Plug-in Extras > Reset Metadata...
3. Choose which metadata to reset (titles, captions, keywords)
4. Confirm the operation
5. The selected metadata will be removed

### Menu Locations
The plugin adds three menu items under **Library > Plug-in Extras**:
- **Lightroom Llama...** - Process individual photos
- **Batch Process with Llama...** - Process multiple photos
- **Reset Metadata...** - Remove generated metadata
The menus are also available in **File > Plug-in Extras**.

## TODO

- [ ] Add support for more LLM models
- [ ] Create settings panel for model configuration
- [ ] Add customizable prompt templates
- [ ] Implement keyword import/export functionality
- [ ] Add support for different image formats
- [ ] Create batch processing presets

## Credits

- [Ollama](https://ollama.com/) - Local AI model hosting
- [minicpm-v](https://github.com/01-ai/Yi) - Vision language model

## Related

- [ChatGPT for Maya](https://github.com/thejoltjoker/chatgpt-for-maya) - Autodesk Maya plugin for context aware chatting with ChatGPT. Get tips, automate tasks and run code.

## You may also like...

- [Lightroom Power Collection](https://github.com/thejoltjoker/lightroom-power-collection) - Lightroom plugin to create a smart collection to semi-automate publishing.

- [Lightroom Workflow](https://github.com/thejoltjoker/lightroom-workflow) - My Lightroom workflow and presets that I have created and use for editing, organizing and exporting my photos.

## License

This project is licensed under the [MIT License](LICENSE).

