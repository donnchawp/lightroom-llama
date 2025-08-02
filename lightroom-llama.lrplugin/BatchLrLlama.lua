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
local LrPrefs = import "LrPrefs"

local logger = LrLogger('BatchLrLlama')
logger:enable("logfile")

local model = "minicpm-v"

logger:info("Initializing Lightroom Llama Batch Processing Plugin")

JSON = (assert(loadfile(LrPathUtils.child(_PLUGIN.path, "JSON.lua"))))()

-- Shared functions (duplicated from LrLlama.lua for now)
local function exportThumbnail(photo)
    local tempPath = LrFileUtils.chooseUniqueFileName(LrPathUtils.getStandardFilePath('temp') .. "/thumbnail.jpg")
    logger:info("Attempting to export thumbnail to: " .. tempPath)

    -- Check if temp directory is accessible
    local tempDir = LrPathUtils.getStandardFilePath('temp')
    if not LrFileUtils.exists(tempDir) then
        logger:error("Temp directory does not exist: " .. tempDir)
        return nil
    end

    local thumbnailSaved = false
    local success, result = photo:requestJpegThumbnail(512, 512, function(jpegData)
        if jpegData then
            local tempFile = io.open(tempPath, "wb")
            if tempFile then
                tempFile:write(jpegData)
                tempFile:close()
                thumbnailSaved = true
                logger:info("Thumbnail saved to " .. tempPath)
                return true
            else
                logger:error("Could not open temp file for writing: " .. tempPath)
                return false
            end
        else
            logger:error("No JPEG data received from photo")
            return false
        end
    end)

    if success and thumbnailSaved then
        -- Verify the file was actually created
        if LrFileUtils.exists(tempPath) then
            logger:info("Thumbnail export successful: " .. tempPath)
            return tempPath
        else
            logger:error("Thumbnail file was not created: " .. tempPath)
            return nil
        end
    else
        logger:warn("Failed to export thumbnail. Success: " .. tostring(success) .. ", Result: " .. tostring(result))
        return nil
    end
end

local function base64EncodeImage(imagePath)
    logger:info("Attempting to encode image: " .. imagePath)

    -- Check if file exists
    if not LrFileUtils.exists(imagePath) then
        logger:error("Image file does not exist: " .. imagePath)
        return nil
    end

    local file = io.open(imagePath, "rb")
    if not file then
        logger:error("Could not open file for reading: " .. imagePath)
        return nil
    end

    local binaryData = file:read("*all")
    file:close()

    if not binaryData or #binaryData == 0 then
        logger:error("No data read from file: " .. imagePath)
        return nil
    end

    local base64Data = LrStringUtils.encodeBase64(binaryData)
    if not base64Data then
        logger:error("Failed to encode image to base64: " .. imagePath)
        return nil
    end

    logger:info("Successfully encoded image to base64. Size: " .. #binaryData .. " bytes")
    return base64Data
end

local function sendDataToApi(photo, prompt, currentData, useCurrentData, useSystemPrompt)
    logger:info("Sending data to API for batch processing")

    -- Try to export thumbnail with retry
    local thumbnailPath = nil
    for attempt = 1, 3 do
        thumbnailPath = exportThumbnail(photo)
        if thumbnailPath then
            break
        end
        logger:warn("Thumbnail export attempt " .. attempt .. " failed, retrying...")
        LrTasks.sleep(0.5) -- Wait 500ms before retry
    end

    if not thumbnailPath then
        return nil, "Failed to export thumbnail after 3 attempts"
    end

    local encodedImage = base64EncodeImage(thumbnailPath)
    if not encodedImage then
        return nil, "Failed to encode image"
    end

    local url = "http://localhost:11434/api/generate"

    local postData = {
        model = model,
        prompt = (useCurrentData and "Title: "..(currentData.title or ""):gsub('"', '\\"') .. " Caption: "..(currentData.caption or ""):gsub('"', '\\"') .. " " .. prompt) or prompt,
        format = "json",
        system = useSystemPrompt and [[# Image Metadata Generation Prompt

You are an expert content curator specializing in creating compelling, accurate metadata for visual content. Your task is to analyze the provided image/video and generate a JSON object with three components: title, caption, and keywords.

## Output Format
Return your response as a valid JSON object with this exact structure:
```json
{
  "title": "string",
  "caption": "string",
  "keywords": ["string", "string", "string"]
}
```

## Guidelines

### Title Requirements
- **Length**: 5-12 words maximum
- **Style**: Write as a descriptive headline, not a sentence
- **Content**: Capture the main subject, action, and context
- **Focus**: Answer "what is happening" in the most compelling way
- **Avoid**: Generic terms, keyword stuffing, colons, redundant phrases
- **Include**: Specific details like location, time of day, or unique elements when relevant

**Good examples:**
- "Mountain climber reaching summit during golden hour"
- "Children playing soccer in urban park"
- "Vintage red bicycle against brick wall"

### Caption Requirements
- **Length**: 15-40 words
- **Style**: Complete sentences that expand on the title
- **Content**: Provide context, mood, or story behind the image
- **Focus**: Add emotional resonance or background information
- **Avoid**: Repeating the exact title wording
- **Include**: Atmosphere, setting details, or cultural context when relevant

**Good example:**
*Title: "Street musician performing violin solo in subway station"*
*Caption: "A talented violinist captivates commuters with classical music during evening rush hour, creating a moment of beauty in the bustling underground transit hub."*

### Keywords Requirements
- **Quantity**: 10-30 keywords (aim for 15-20 for optimal results)
- **Hierarchy**: Order from most specific to more general
- **Categories**: Include subjects, actions, emotions, locations, styles, colors, concepts
- **Format**: Single words or short phrases (2-3 words max)
- **Avoid**: Repeating title/caption words exactly, overly generic terms, technical camera specs

**Keyword categories to consider:**
- Primary subjects (people, objects, animals)
- Actions and verbs
- Emotions and moods
- Locations and settings
- Colors and lighting
- Art styles or techniques
- Concepts and themes
- Seasonal or temporal elements

## Quality Checklist
Before finalizing, ensure:
- [ ] Title is unique and descriptive without being generic
- [ ] Caption adds meaningful context beyond the title
- [ ] Keywords cover multiple relevant categories
- [ ] No unnecessary repetition across all three elements
- [ ] JSON format is valid and properly structured
- [ ] Content accurately reflects what's actually in the image

## Example Output
```json
{
  "title": "Barista creating latte art in cozy downtown cafe",
  "caption": "Skilled coffee artist carefully pours steamed milk to create an intricate leaf pattern, showcasing the craftsmanship behind specialty coffee culture in a warm, inviting neighborhood coffee shop.",
  "keywords": ["barista", "latte art", "coffee shop", "cafe culture", "milk foam", "artisan", "beverage preparation", "downtown", "craftsmanship", "morning routine", "specialty coffee", "hospitality", "small business", "urban lifestyle", "food service"]
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
        local prefs = LrPrefs.prefsForPlugin()

        -- Initialize with default values or saved preferences
        props.prompt = prefs.batchPrompt or "Caption this photo"
        props.useCurrentData = prefs.batchUseCurrentData or false
        props.useSystemPrompt = prefs.batchUseSystemPrompt ~= false -- Default to true
        props.skipExisting = prefs.batchSkipExisting ~= false -- Default to true
        props.generateTitle = prefs.batchGenerateTitle ~= false -- Default to true
        props.generateCaption = prefs.batchGenerateCaption ~= false -- Default to true
        props.generateKeywords = prefs.batchGenerateKeywords ~= false -- Default to true

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

                f:static_text{
                    title = "Generate:",
                    font = "<system/bold>"
                },
                f:spacer{height = 10},

                f:checkbox{
                    title = "Title",
                    value = LrView.bind("generateTitle")
                },
                f:spacer{height = 5},

                f:checkbox{
                    title = "Caption",
                    value = LrView.bind("generateCaption")
                },
                f:spacer{height = 5},

                f:checkbox{
                    title = "Keywords",
                    value = LrView.bind("generateKeywords")
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
            -- Save preferences for next time
            prefs.batchPrompt = props.prompt
            prefs.batchUseCurrentData = props.useCurrentData
            prefs.batchUseSystemPrompt = props.useSystemPrompt
            prefs.batchSkipExisting = props.skipExisting
            prefs.batchGenerateTitle = props.generateTitle
            prefs.batchGenerateCaption = props.generateCaption
            prefs.batchGenerateKeywords = props.generateKeywords

            local settings = {
                prompt = props.prompt,
                useCurrentData = props.useCurrentData,
                useSystemPrompt = props.useSystemPrompt,
                skipExisting = props.skipExisting,
                generateTitle = props.generateTitle,
                generateCaption = props.generateCaption,
                generateKeywords = props.generateKeywords
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

                        if settings.generateTitle and apiResponse.title then
                            photo:setRawMetadata("title", apiResponse.title)
                        end
                        if settings.generateCaption and apiResponse.caption then
                            photo:setRawMetadata("caption", apiResponse.caption)
                        end
                        if settings.generateKeywords and apiResponse.keywords then
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
