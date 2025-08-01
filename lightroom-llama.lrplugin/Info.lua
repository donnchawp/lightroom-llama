return {
    VERSION = {
        major = 1,
        minor = 0,
        revision = 0
    },
    LrPluginName = "Lightroom Llama",
    LrPluginDescription = "Description of your Lightroom plugin",
    LrToolkitIdentifier = "com.thejoltjoker.lightroom.llama",
    LrPluginInfoUrl = "https://github.com/thejoltjoker/lightroom-llama",
    LrPluginInfoUrlProvider = "http://www.thejoltjoker.com",
    LrSdkVersion = 10.0,
    LrSdkMinimumVersion = 5.0,
    LrLibraryMenuItems = {{
        title = "Lightroom Llama...",
        file = "LrLlama.lua"
    }, {
        title = "Batch Process with Llama...",
        file = "BatchLrLlama.lua",
        enabledWhen = "photosSelected"
    }},
    LrExportMenuItems = {{
        title = "Batch Process with Llama...",
        file = "BatchLrLlama.lua",
        enabledWhen = "photosSelected"
    }}
}
