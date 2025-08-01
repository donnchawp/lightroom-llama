local LrHttp = import 'LrHttp'
local LrPathUtils = import 'LrPathUtils'
local LrLogger = import 'LrLogger'
local LrApplication = import "LrApplication"
local LrErrors = import "LrErrors"
local LrDialogs = import "LrDialogs"
local LrView = import "LrView"
local LrTasks = import "LrTasks"
local LrFunctionContext = import "LrFunctionContext"
local LrFileUtils = import 'LrFileUtils'
local LrStringUtils = import 'LrStringUtils'
local LrBinding = import "LrBinding"
local LrColor = import "LrColor"
local LrProgressScope = import "LrProgressScope"

local logger = LrLogger('BatchLrLlama')
logger:enable("logfile")

local model = "minicpm-v"

logger:info("Initializing Lightroom Llama Batch Processing Plugin")

JSON = (assert(loadfile(LrPathUtils.child(_PLUGIN.path, "JSON.lua"))))()

-- Shared functions (duplicated from LrLlama.lua for now)
local function exportThumbnail(photo)
    local tempPath = LrFileUtils.chooseUniqueFileName(LrPathUtils.getStandardFilePath('temp') .. "/thumbnail.jpg")

    local success, result = photo:requestJpegThumbnail(512, 512, function(jpegData)
        if jpegData then
            local tempFile = io.open(tempPath, "wb")
            tempFile:write(jpegData)
            tempFile:close()
            logger:info("Thumbnail saved to " .. tempPath)
            return true
        end
        return false
    end)

    if success then
        return tempPath
    else
        logger:warn("Failed to export thumbnail")
        return nil
    end
end

local function base64EncodeImage(imagePath)
    local file = io.open(imagePath, "rb")
    if not file then
        logger:error("Could not open file: " .. imagePath)
        return nil
    end

    local binaryData = file:read("*all")
    file:close()

    local base64Data = LrStringUtils.encodeBase64(binaryData)
    return base64Data
end

local function sendDataToApi(photo, prompt, currentData, useCurrentData, useSystemPrompt)
    logger:info("Sending data to API for batch processing")
    local thumbnailPath = exportThumbnail(photo)
    if not thumbnailPath then
        return nil, "Failed to export thumbnail"
    end
    
    local encodedImage = base64EncodeImage(thumbnailPath)
    if not encodedImage then
        return nil, "Failed to encode image"
    end
    
    local url = "http://localhost:11434/api/generate"

    local postData = {
        model = model,
        prompt = (useCurrentData and "Title: "..currentData.title .. " Caption: "..currentData.caption .. prompt) or prompt,
        format = "json",
        system = useSystemPrompt and [[You are an AI tasked with creating a JSON object containing a `title`, a `caption`, and a list of `keywords` based on a given piece of content (such as an image or video). 

Please follow these detailed guidelines for creating excellent metadata:

1. **Title (Description):**
   - Provide a unique, descriptive title for the content.
   - The title should answer the Who, What, When, Where, and Why of the content.
   - It should be written as a sentence or phrase, similar to a news headline, capturing the key details, mood, and emotions of the scene.
   - Do not list keywords in the title. Avoid repetition of words and phrases.
   - Include helpful details such as the angle, focus, and perspective if relevant.
   - Do not include :.
   - If given, use the current title as a starting point.

2. **Caption:**
   - Provide a more detailed description or context for the content. This can be a fuller explanation of the title, including any relevant background or emotional tone that helps convey the essence of the scene.
   - If given, use the current caption as a starting point.

3. **Keywords:**
   - Provide a list of 7 to 50 keywords.
   - Keywords should be specific and directly related to the content.
   - Include broader topics, feelings, concepts, or associations represented by the content.
   - Avoid using unrelated terms or repeating words or compound words.
   - Do not include links, camera information, or trademarks unless required for editorial content.

### JSON Format:
```json
{
  "title": "string",
  "caption": "string", 
  "keywords": ["string"]
}
```

Use this structure and guidelines to generate titles, captions, and keywords that are descriptive, unique, and accurate.]] or
[[You are an AI tasked with creating a JSON object containing a `title`, a `caption`, and a list of `keywords` based on a given piece of content (such as an image or video).

### JSON Format:
```json
{
  "title": "string",
  "caption": "string",
  "keywords": ["string"]
}
```
]],
        images = {encodedImage},
        stream = false
    }

    local jsonPayload = JSON:encode(postData)

    local response, headers = LrHttp.post(url, jsonPayload, {{
        field = "Content-Type",
        value = "application/json"
    }})

    -- Clean up thumbnail file
    LrFileUtils.delete(thumbnailPath)

    if response then
        local response_data = JSON:decode(response)
        local response_json = JSON:decode(response_data.response)
        return response_json, nil
    else
        return nil, "Failed to send data to the API"
    end
end

local function addKeywordsWithParent(catalog, photo, keywords)
    if not keywords or type(keywords) ~= "table" then
        return
    end
    
    -- First create or get the parent 'llm' keyword
    local llmKeyword = catalog:createKeyword("llm", nil, true, nil, true)
    if not llmKeyword then
        error("Failed to create or get 'llm' parent keyword")
    end
    
    for _, keyword in ipairs(keywords) do
        if keyword and keyword ~= "" then
            -- Create child keyword under 'llm' parent
            local childKeyword = catalog:createKeyword(keyword, nil, true, llmKeyword, true)
            if childKeyword then
                -- Add the keyword object to the photo
                photo:addKeyword(childKeyword)
            else
                logger:warn("Failed to create keyword: " .. tostring(keyword))
            end
        end
    end
end

local function getLlmKeywordsFromPhoto(photo)
    local llmKeywords = {}
    
    -- Wrap in pcall to catch any errors
    local success, result = pcall(function()
        local allKeywords = photo:getRawMetadata("keywords")
        
        if allKeywords then
            for _, keyword in ipairs(allKeywords) do
                local parent = keyword:getParent()
                if parent and parent:getName() == "llm" then
                    table.insert(llmKeywords, keyword:getName())
                end
            end
        end
    end)
    
    if not success then
        logger:warn("Error getting LLM keywords: " .. tostring(result))
        return {} -- Return empty array on error
    end
    
    return llmKeywords
end

-- Batch processing functions
local function processPhotosApiOnly(photos, settings)
    local results = {}
    
    -- Only do API processing, no metadata saving
    for i, photo in ipairs(photos) do
        local result = {
            photo = photo,
            success = false,
            error = nil,
            metadata = nil
        }
        
        -- Get current metadata
        local currentData = {
            title = photo:getFormattedMetadata('title') or "",
            caption = photo:getFormattedMetadata('caption') or ""
        }
        
        -- Process photo with API
        local apiResponse, apiError = sendDataToApi(photo, settings.prompt, currentData, settings.useCurrentData, settings.useSystemPrompt)
        
        if apiResponse then
            result.success = true
            result.metadata = apiResponse
        else
            result.error = apiError or "Unknown API error"
        end
        
        table.insert(results, result)
        
        -- Small delay between photos
        LrTasks.sleep(0.5)
    end
    
    return results
end

local function saveResultsMetadata(catalog, results)
    -- Save metadata outside of async task context
    for _, result in ipairs(results) do
        if result.success and result.metadata then
            local apiResponse = result.metadata
            local photo = result.photo
            
            local saveSuccess, saveError = pcall(function()
                catalog:withWriteAccessDo("Save Llama metadata", function()
                    if apiResponse.title then
                        photo:setRawMetadata("title", apiResponse.title)
                    end
                    if apiResponse.caption then
                        photo:setRawMetadata("caption", apiResponse.caption)
                    end
                end)
            end)
            
            if not saveSuccess then
                result.success = false
                result.error = "Failed to save metadata: " .. tostring(saveError)
            end
        end
    end
    
    return results
end

local function showBatchResults(results)
    local successful = 0
    local failed = 0
    local skipped = 0
    
    for _, result in ipairs(results) do
        if result.success then
            if result.error and string.find(result.error, "Skipped") then
                skipped = skipped + 1
            else
                successful = successful + 1
            end
        else
            failed = failed + 1
        end
    end
    
    -- Only show popup if there are failures
    if failed > 0 then
        local message = string.format(
            "Batch processing complete!\n\nSuccessful: %d\nSkipped: %d\nFailed: %d\n\nTotal processed: %d photos",
            successful, skipped, failed, #results
        )
        
        local failedPhotos = {}
        for _, result in ipairs(results) do
            if not result.success then
                local photoName = result.photo:getFormattedMetadata('fileName') or "Unknown"
                table.insert(failedPhotos, photoName .. ": " .. (result.error or "Unknown error"))
            end
        end
        
        message = message .. "\n\nFailed photos:\n" .. table.concat(failedPhotos, "\n")
        
        LrDialogs.message("Batch Processing Results", message, "info")
    end
    -- If all successful, no popup is shown
end

local function showBatchDialog(selectedPhotos)
    LrFunctionContext.callWithContext("showBatchDialog", function(context)
        local props = LrBinding.makePropertyTable(context)
        props.prompt = "Caption this photo"
        props.useCurrentData = false
        props.useSystemPrompt = true
        props.skipExisting = true
        
        local f = LrView.osFactory()
        
        local c = f:view{
            bind_to_object = props,
            f:column{
                f:static_text{
                    title = string.format("Batch process %d selected photos with Llama", #selectedPhotos),
                    font = "<system/bold>"
                },
                f:spacer{height = 20},
                
                f:static_text{
                    title = "Prompt:"
                },
                f:spacer{f:label_spacing{}},
                f:edit_field{
                    value = LrView.bind("prompt"),
                    width = 400,
                    height = 60
                },
                f:spacer{height = 15},
                
                f:checkbox{
                    title = "Use current title and caption data",
                    value = LrView.bind("useCurrentData")
                },
                f:spacer{height = 10},
                
                f:checkbox{
                    title = "Use system prompt (recommended)",
                    value = LrView.bind("useSystemPrompt")
                },
                f:spacer{height = 10},
                
                f:checkbox{
                    title = "Skip photos that already have LLM keywords",
                    value = LrView.bind("skipExisting")
                },
                f:spacer{height = 20},
                
                f:separator{width = 400},
                f:spacer{height = 10},
                
                f:static_text{
                    title = "Model: " .. model,
                    font = "<system>"
                },
                f:spacer{height = 10},
                
                f:static_text{
                    title = "Note: This process may take several minutes depending on the number of photos.",
                    font = "<system>",
                    text_color = LrColor(0.6, 0.6, 0.6)
                }
            }
        }
        
        local result = LrDialogs.presentModalDialog({
            title = "Batch Process with Llama",
            contents = c,
            actionVerb = "Start Processing"
        })
        
        if result == "ok" then
            local settings = {
                prompt = props.prompt,
                useCurrentData = props.useCurrentData,
                useSystemPrompt = props.useSystemPrompt,
                skipExisting = props.skipExisting
            }
            
            -- Process with progress scope
            local results = {}
            local catalog = LrApplication.activeCatalog()
            
            LrFunctionContext.callWithContext("batchProcessing", function(context)
                local progressScope = LrProgressScope({
                    title = "Processing photos with Llama",
                    functionContext = context
                })
                
                progressScope:setPortionComplete(0, #selectedPhotos)
                
                for i, photo in ipairs(selectedPhotos) do
                    if progressScope:isCanceled() then
                        break
                    end
                    
                    local photoName = photo:getFormattedMetadata('fileName') or "Photo " .. i
                    progressScope:setCaption("Processing: " .. photoName)
                    
                    local result = {
                        photo = photo,
                        success = false,
                        error = nil,
                        metadata = nil
                    }
                    
                    -- Check if we should skip photos with existing LLM keywords
                    local shouldSkip = false
                    if settings.skipExisting then
                        local existingKeywords = getLlmKeywordsFromPhoto(photo)
                        if #existingKeywords > 0 then
                            result.success = true
                            result.error = "Skipped - already has LLM keywords"
                            shouldSkip = true
                        end
                    end
                    
                    if not shouldSkip then
                        -- Get current metadata
                        local currentData = {
                            title = photo:getFormattedMetadata('title') or "",
                            caption = photo:getFormattedMetadata('caption') or ""
                        }
                        
                        -- Process photo with API
                        local apiResponse, apiError = sendDataToApi(photo, settings.prompt, currentData, settings.useCurrentData, settings.useSystemPrompt)
                        
                        if apiResponse then
                            result.success = true
                            result.metadata = apiResponse
                        else
                            result.error = apiError or "Unknown API error"
                        end
                    end
                    
                    table.insert(results, result)
                    progressScope:setPortionComplete(i, #selectedPhotos)
                end
                
                progressScope:done()
            end)
            
            -- Save all metadata in a single write access call
            catalog:withWriteAccessDo("Save Llama batch metadata", function()
                for _, result in ipairs(results) do
                    if result.success and result.metadata then
                        local apiResponse = result.metadata
                        local photo = result.photo
                        
                        if apiResponse.title then
                            photo:setRawMetadata("title", apiResponse.title)
                        end
                        if apiResponse.caption then
                            photo:setRawMetadata("caption", apiResponse.caption)
                        end
                        if apiResponse.keywords then
                            addKeywordsWithParent(catalog, photo, apiResponse.keywords)
                        end
                    end
                end
            end)
            
            showBatchResults(results)
        end
    end)
end

-- Main batch processing function
local function main()
    local catalog = LrApplication.activeCatalog()
    local selectedPhotos = catalog:getTargetPhotos()
    
    if #selectedPhotos == 0 then
        LrDialogs.message("No photos selected", "Please select one or more photos to process.", "critical")
        return
    end
    
    if #selectedPhotos == 1 then
        local result = LrDialogs.confirm("Single photo selected", 
            "You have selected only one photo. Would you like to use the regular Lightroom Llama dialog instead?",
            "Use Regular Dialog", "Continue with Batch", "Cancel")
        
        if result == "ok" then
            -- Could call the regular dialog here, but for now just return
            LrDialogs.message("Suggestion", "Please use the 'Lightroom Llama...' menu item for single photos.", "info")
            return
        elseif result == "cancel" then
            return
        end
    end
    
    showBatchDialog(selectedPhotos)
end

LrTasks.startAsyncTask(main)