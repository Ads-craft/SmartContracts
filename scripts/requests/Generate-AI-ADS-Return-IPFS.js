/**
 * @notice chainlink function that creates ads for ticktok and returns an IPFS string representation to the corresponding blockchain
 * 
 */


const url = "http://localhost:3500/upload-generated-ads"

const response = Functions.makeHttpRequest({url,data:{
    
}})
const responseJSON = await response;
console.log(responseJSON.data);

if(responseJSON.error) throw new Error("Error: " + responseJSON.message);

return Functions.encodeString(responseJSON.data);