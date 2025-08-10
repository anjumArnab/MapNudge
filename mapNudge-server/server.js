const express = require('express');
const http = require('http');
const socketIo = require('socket.io');
const cors = require('cors');

const app = express();
const server = http.createServer(app);
const io = socketIo(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

const PORT = process.env.PORT || 3000;

// Middleware
app.use(cors());
app.use(express.json());

// Store room data and user locations
const rooms = new Map();
const userLocations = new Map();

// Basic route to check server status
app.get('/', (req, res) => {
  res.json({
    message: 'Location Sharing Server is running!',
    timestamp: new Date().toISOString(),
    activeRooms: rooms.size,
    connectedUsers: userLocations.size
  });
});

// Get room info
app.get('/room/:roomId', (req, res) => {
  const { roomId } = req.params;
  const room = rooms.get(roomId);
  
  if (!room) {
    return res.json({
      exists: false,
      users: [],
      message: 'Room not found'
    });
  }
  
  res.json({
    exists: true,
    users: Array.from(room.users.keys()),
    userCount: room.users.size,
    locations: Object.fromEntries(room.users)
  });
});

// Socket.io connection handling
io.on('connection', (socket) => {
  console.log(`New client connected: ${socket.id}`);
  
  // Handle user joining a room
  socket.on('join-room', (data) => {
    const { roomId, userId } = data;
    
    console.log(`User ${userId} joining room ${roomId}`);
    
    // Leave any previous room
    socket.rooms.forEach(room => {
      if (room !== socket.id) {
        socket.leave(room);
      }
    });
    
    // Join the new room
    socket.join(roomId);
    
    // Initialize room if it doesn't exist
    if (!rooms.has(roomId)) {
      rooms.set(roomId, {
        users: new Map(),
        createdAt: new Date().toISOString()
      });
    }
    
    const room = rooms.get(roomId);
    
    // Add user to room
    room.users.set(userId, {
      socketId: socket.id,
      latitude: null,
      longitude: null,
      lastUpdate: null
    });
    
    // Store user info in socket for cleanup
    socket.userId = userId;
    socket.roomId = roomId;
    
    // Send confirmation to the user
    socket.emit('joined-room', {
      success: true,
      roomId,
      userId,
      message: `Successfully joined room ${roomId}`,
      usersInRoom: Array.from(room.users.keys())
    });
    
    // Notify other users in the room
    socket.to(roomId).emit('user-joined', {
      userId,
      message: `${userId} joined the room`,
      usersInRoom: Array.from(room.users.keys())
    });
    
    // Send existing locations to the new user
    const existingLocations = {};
    room.users.forEach((userData, user) => {
      if (userData.latitude && userData.longitude && user !== userId) {
        existingLocations[user] = {
          latitude: userData.latitude,
          longitude: userData.longitude,
          lastUpdate: userData.lastUpdate
        };
      }
    });
    
    if (Object.keys(existingLocations).length > 0) {
      socket.emit('existing-locations', existingLocations);
    }
    
    console.log(`Room ${roomId} now has ${room.users.size} users`);
  });
  
  // Handle location sharing
  socket.on('share-location', (data) => {
    const { roomId, userId, latitude, longitude } = data;
    
    console.log(`Location update from ${userId} in room ${roomId}: ${latitude}, ${longitude}`);
    
    const room = rooms.get(roomId);
    if (!room || !room.users.has(userId)) {
      socket.emit('error', {
        message: 'User not found in room or room does not exist'
      });
      return;
    }
    
    // Update user location
    const userData = room.users.get(userId);
    userData.latitude = latitude;
    userData.longitude = longitude;
    userData.lastUpdate = new Date().toISOString();
    
    // Broadcast location to all other users in the room
    socket.to(roomId).emit('location-update', {
      userId,
      latitude,
      longitude,
      timestamp: userData.lastUpdate
    });
    
    // Send confirmation to sender
    socket.emit('location-shared', {
      success: true,
      message: 'Location shared successfully',
      timestamp: userData.lastUpdate
    });
    
    console.log(`Location broadcasted to room ${roomId}`);
  });
  
  // Handle getting all locations in room
  socket.on('get-all-locations', (data) => {
    const { roomId } = data;
    
    const room = rooms.get(roomId);
    if (!room) {
      socket.emit('error', {
        message: 'Room not found'
      });
      return;
    }
    
    const allLocations = {};
    room.users.forEach((userData, userId) => {
      if (userData.latitude && userData.longitude) {
        allLocations[userId] = {
          latitude: userData.latitude,
          longitude: userData.longitude,
          lastUpdate: userData.lastUpdate
        };
      }
    });
    
    socket.emit('all-locations', allLocations);
  });
  
  // Handle user leaving room
  socket.on('leave-room', () => {
    handleUserDisconnection(socket);
  });
  
  // Handle disconnection
  socket.on('disconnect', () => {
    console.log(`Client disconnected: ${socket.id}`);
    handleUserDisconnection(socket);
  });
  
  // Function to handle user disconnection cleanup
  function handleUserDisconnection(socket) {
    if (socket.userId && socket.roomId) {
      const room = rooms.get(socket.roomId);
      if (room && room.users.has(socket.userId)) {
        room.users.delete(socket.userId);
        
        // Notify other users
        socket.to(socket.roomId).emit('user-left', {
          userId: socket.userId,
          message: `${socket.userId} left the room`,
          usersInRoom: Array.from(room.users.keys())
        });
        
        // Clean up empty rooms
        if (room.users.size === 0) {
          rooms.delete(socket.roomId);
          console.log(`Room ${socket.roomId} deleted (empty)`);
        }
        
        console.log(`User ${socket.userId} left room ${socket.roomId}`);
      }
    }
  }
});

// Error handling
process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
});

process.on('unhandledRejection', (error) => {
  console.error('Unhandled Rejection:', error);
});

// Start server
server.listen(PORT, () => {
  console.log(`Location Sharing Server running on port ${PORT}`);
  console.log(`Server URL: http://localhost:${PORT}`);
  console.log(`Use ngrok to create public URL: ngrok http ${PORT}`);
});

module.exports = { app, server, io };