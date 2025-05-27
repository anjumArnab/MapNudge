# MapNudge
This application enables real-time location sharing using Socket.IO and Google Maps integration. Send coordinates from one view and visualize them instantly on an interactive map.

## Technology Stack

- **Flutter**: Client-side app for UI
- **Socket.IO**: For sharing data

const http = require("http");
const server = http.createServer();
const {Server} = require("socket.io");
const io = new Server(server);

const PORT = process.env.PORT 

io.on("connection", (socket)=>{
    socket.on("position-change", (data)=>{
        io.emit("position-change", data);
    });
    socket.on("disconnect", ()=> {

    });
});

server.listen(PORT, () => {
    consol.log("listening on ${PORT}");
});