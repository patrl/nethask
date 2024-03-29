-- apecs requires these:
{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE ScopedTypeVariables        #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# LANGUAGE TypeApplications           #-}
{-# LANGUAGE TypeFamilies               #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

-- These are extra things we need.
{-# LANGUAGE OverloadedLists #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import           Apecs -- we're going to use this for our game logic
import           SDL                            ( ($=) )
import qualified SDL -- the main sdl2 bindings
-- TODO figure out if juicypixels can replace this, although it's probably slower.
import qualified SDL.Image                     as SDLImg -- necessary to load the brogue font
-- import qualified SDL.Font                      as TTF
import           SDL.Vect -- We need this for the vector constructors
import           Control.Monad                  ( unless
                                                , void
                                                ) -- a handy utility for breaking a loop
import           Data.Maybe                     ( fromMaybe )
import           Foreign.C.Types                ( CInt
                                                , CFloat
                                                ) -- since we dealing with a C FFI library, we need to deal with C Integer types
import           Data.Word                      ( Word8 ) -- RGBA colors are stored in this format
import           Control.Lens                   ( (^.) )
import qualified Data.Vector                   as V
import qualified Math.Geometry.Grid            as Grid
import           Math.Geometry.Grid.Square
import           Math.Geometry.Grid.SquareInternal
                                                ( SquareDirection
                                                  ( North
                                                  , East
                                                  , South
                                                  , West
                                                  )
                                                )

-- apecs stuff:

newtype Position = Position (Int,Int) deriving Show
instance Component Position where type Storage Position = Map Position

data Player = Player deriving Show
instance Component Player where type Storage Player = Unique Player

makeWorld "World" [''Position, ''Player]

type System' a = System World a

playerPos :: (Int, Int)
playerPos = (40, 30)

initialize :: System' ()
initialize = void $ newEntity (Player, Position playerPos)

move :: Grid.Direction RectSquareGrid -> (Int, Int) -> (Int, Int)
move dir initPos = fromMaybe initPos (Grid.neighbour screenGrid initPos dir)

handleInput :: (SDL.Scancode -> Bool) -> System' ()
handleInput kmap = if
  | (kmap SDL.ScancodeUp) -> cmap $ \(Player, Position pos) -> Position (move North pos)
  | (kmap SDL.ScancodeRight) -> cmap $ \(Player, Position pos) -> Position (move East pos)
  | (kmap SDL.ScancodeDown) -> cmap $ \(Player, Position pos) -> Position (move South pos)
  | (kmap SDL.ScancodeLeft) -> cmap $ \(Player, Position pos) -> Position (move West pos)
  | otherwise -> return ()

fontName :: FilePath
fontName = "cp437_20x20.png"

-- directory where resources reside.
resourceDir :: FilePath
resourceDir = "data/"

-- screen height and width in tiles.
screenDims :: V2 CInt
screenDims = V2 80 60

-- screenGrid
screenGrid :: RectSquareGrid
screenGrid = rectSquareGrid (fromIntegral $ screenDims ^. _y)
                            (fromIntegral $ screenDims ^. _x)

-- screen grid index to rect
screenGridIndexToRect :: (Int, Int) -> V2 CInt -> SDL.Rectangle CInt
screenGridIndexToRect (xCoord, yCoord) tileDims =
  mkRect (V2 (fromIntegral xCoord) (fromIntegral yCoord) * tileDims) tileDims

scalingFactor :: V2 CFloat
scalingFactor = V2 1.0 1.0

_font13grid :: V2 CInt
_font13grid = V2 16 16

-- TODO find out if there's a nice library for interfacing with RGBA data
-- some handy color aliases
black, white, _clearColor, dracBlack, dracRed, dracGreen, dracYellow :: V4 Word8
black = V4 0 0 0 0
white = V4 maxBound maxBound maxBound 0
_clearColor = dracBlack

dracBlack = V4 40 42 54 0
dracRed = V4 maxBound 85 85 0
dracGreen = V4 80 250 123 0
dracYellow = V4 241 250 140 0


-- takes a texture atlas, together with the rows/columns, and returns an SDL surface
-- together with the dimensions of each tile.
loadSurfaceWithTileDims
  :: FilePath -> V2 CInt -> IO (SDL.Surface, V2 CInt, V2 CInt)
loadSurfaceWithTileDims path gridDims = do
  surface     <- SDLImg.load $ resourceDir ++ path
  surfaceDims <- SDL.surfaceDimensions surface
  return
    ( surface
    , surfaceDims
    , V2 (surfaceDims ^. _x `div` gridDims ^. _x)
         (surfaceDims ^. _y `div` gridDims ^. _y)
    )

-- takes a surface, and loads it as a texture, discarding the surface from memory.
loadTextureFromSurface :: SDL.Surface -> SDL.Renderer -> IO SDL.Texture
loadTextureFromSurface surface renderer = do
  newTexture <- SDL.createTextureFromSurface renderer surface
  SDL.freeSurface surface
  return newTexture

-- a helper function from two 2-dimensional vectors to an SDL rectangle.
mkRect :: V2 CInt -> V2 CInt -> SDL.Rectangle CInt
mkRect p = SDL.Rectangle (P p)

-- takes some texture dimensions, and grid dimensions, and returns.
mkRects :: V2 CInt -> V2 CInt -> IO (V.Vector (SDL.Rectangle CInt))
mkRects textDims gDims = do
  let cDims =
        V2 (textDims ^. _x `div` gDims ^. _x) (textDims ^. _y `div` gDims ^. _y)
  return $ V.fromList
    [ mkRect (V2 px py) cDims
    | px <- [0, cDims ^. _x .. (textDims ^. _x - cDims ^. _x)]
    , py <- [0, cDims ^. _y .. (textDims ^. _y - cDims ^. _y)]
    ]

main :: IO ()
main = do
  SDL.initialize ([SDL.InitVideo] :: [SDL.InitFlag])

  -- load font, and get the dimensions of each tile
  (atlasSurface, surfaceDims, tileDims) <- loadSurfaceWithTileDims fontName
                                                                   _font13grid
  putStrLn $ "the dimensions of each tile are:" ++ show tileDims -- for debugging purposes

  -- compute the rectangles corresponding to each tile
  rects  <- mkRects surfaceDims _font13grid

  window <- SDL.createWindow
    "SDL Tutorial"
    SDL.defaultWindow { SDL.windowInitialSize = screenDims * tileDims
                      , SDL.windowHighDPI     = True
                      , SDL.windowMode        = SDL.Fullscreen
                      } -- load a window -- the dimension is a multiple of tile size

  renderer      <- SDL.createRenderer window (-1) SDL.defaultRenderer -- creates the rendering context

  _             <- SDL.rendererScale renderer SDL.$= scalingFactor

  _             <- SDL.rendererDrawColor renderer SDL.$= _clearColor

  brogueTexture <- loadTextureFromSurface atlasSurface renderer

  let broguePrintChar charNum gridCoords = SDL.copy
        renderer
        brogueTexture
        (Just $ rects V.! charNum)
        (Just $ screenGridIndexToRect gridCoords tileDims)

  let
    loop = do
      events <- map SDL.eventPayload <$> SDL.pollEvents
      let quit = SDL.QuitEvent `elem` events
      _ <- SDL.rendererDrawColor renderer SDL.$= _clearColor
      SDL.clear renderer
      broguePrintChar 16 (40, 30)
      _ <- SDL.rendererDrawColor renderer SDL.$= dracRed
      _ <- SDL.fillRect renderer
                        (Just $ screenGridIndexToRect (0, 0) (tileDims * 8))
      -- sequence_ [ broguePrintChar 16 coords | coords <- Grid.centre screenGrid ]
      SDL.present renderer
      unless quit loop
  loop

  SDL.destroyTexture brogueTexture
  SDL.destroyRenderer renderer
  SDL.destroyWindow window

  SDL.quit
