// express = require('express');
import express from 'express';
const PORT =process.env.PORT ||3000;
const app = express();

app.get('/', function(req, res){
    res.json({twisted: true});
});

app.post("/upload-generated-ads", function(req, res){

});
app.listen(PORT, () => console.log("listening on port: " + PORT))
export default app;

