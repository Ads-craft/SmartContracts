import axios from "axios";
import * as dotenv from "dotenv";
dotenv.config();
    
const OPEN_AI_KEY = process.env.OPEN_AI_KEY;
const OPEN_AI_URL = process.env.OPEN_AI_URL;  

export async function makePromptRequest(textPrompt){
    try {
            const numImages = 1;
            const headers = {
                "Content-Type": "application/json",
                Authorization: `Bearer ${OPEN_AI_KEY}`,
            };

            const data = {
                prompt: textPrompt,
                n: numImages,
                model: "dall-e-3",
                size: "1024x1024",
            };

            const response = await axios.post(OPEN_AI_URL, data, { headers });
            const responseData = await response?.data;
            return responseData;
    } catch (error) {
        console.log(error)
        return null;
    }

}

async function main(){
    const image = await makePromptRequest("fly with a cool rasterized eyes");
    console.log(image)
}

main().catch(error=>{
    console.log(error)
    process.exit(1);
})

