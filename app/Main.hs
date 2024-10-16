{-# LANGUAGE OverloadedStrings #-}

module Main where

import IHP.HSX.QQ (hsx)
import Text.Blaze.Html.Renderer.String (renderHtml)
import Text.Blaze.Html (Html)

import Data.Text (unpack)
import Data.List (intercalate, find)

import System.Directory (doesFileExist)

import Network.Wai (responseBuilder, responseFile, Request (queryString))
import Network.Wai.Handler.Warp (run)
import Network.Wai.Internal (Response(ResponseBuilder, ResponseFile), Request, pathInfo, requestMethod)
import Network.HTTP.Types (statusCode, status200, status404, Status, Query, HeaderName)
import Blaze.ByteString.Builder (copyByteString)
import Data.ByteString.UTF8 (fromString, ByteString)

import Layout (layout)

import Index (index)
import Pages.Contact.Contact (contact)
import Pages.Projects.Projects (projects)
import Pages.Projects.Snake (leaderboard)
import Pages.Sources.Sources (sources)
import Pages.Guestbook.Guestbook (guestbook)

import Database.Database (doMigration)
import Utils (unpackBS)
import Settings (getPort, getCliState, getMigrate)
import Logger (logger, tableify, info, warning)
import Api.Api (api)
import Control.Concurrent (forkIO, ThreadId)
import Repl (repl)
import System.Environment (getArgs)
import Pages.Admin.Admin (admin)
import Text.Regex (mkRegex, Regex, matchRegex)
import Pages.Pages (findPage)
import Data.List.Split (splitOn)
import Control.Monad (when)
import Page (embedText, embedImage, description)


serve :: Html -> Response
serve content = responseBuilder status200 [("Content-Type", "text/html")] $ copyByteString (fromString (renderHtml content))

autoContentType :: String -> (HeaderName, ByteString)
autoContentType path = ("Content-Type", mime extension)
    where
        extension = last (splitOn "." path)
        mime "js" = "application/javascript"
        mime "png" = "image/png"
        mime "svg" = "image/svg+xml"
        mime "css" = "text/css"
        mime _ = "text/plain"

serveFile :: String -> IO Response
serveFile path = do
    info "Serving file"
    exists <- doesFileExist path
    if exists then do
        info "File exists"

        return $ responseFile status200 [autoContentType path] path Nothing
    else do
        warning "No file found!"
        return $ responseBuilder status404 [("Content-Type", "text/json")] $ copyByteString "{\"error\":\"Error: file not found!\"}"

app :: Request -> (Response -> IO b)  -> IO b
app request respond = do
    let xs = map unpack $ pathInfo request
    let x = if null xs then "" else head xs
    let args = "/" ++ intercalate "/" xs
    response <- if x == "static" then do -- If the requested content is a file
        serveFile $ intercalate "/" xs

    else if x == "favicon.ico" then do -- If the requested file is the icon file
        serveFile "static/favicon.ico"

    else if x == "api" then do -- If the request is to the API
        (status, value, headers) <- api (drop 1 xs) request
        return $ responseBuilder status headers $ copyByteString (fromString value)

    else do -- If the content is to the HTML Frontend
        let (settings, page) = findPage args
        result <- page request
        let image = if embedImage settings /= "" then [hsx|
            <meta content={embedImage settings} property="og:image">
        |] else [hsx||]
        let text = if embedText settings /= "" then [hsx|
            <meta content={embedText settings} property="og:title">
        |] else [hsx||]
        let desc = if description settings /= "" then [hsx|
            <meta content={description settings} property="og:description">
        |] else [hsx||]

        return $ serve (mconcat [result, image, text, desc])

    logger request response
    respond response

main :: IO ()
main = do
    port <- getPort
    info $ "Listening on " ++ show port
    putStrLn $ "+" ++ mconcat (replicate 65 "-") ++ "+"
    putStrLn $ tableify ["METHOD", "STATUS", "PATH"]
    putStrLn $ "+" ++ mconcat (replicate 65 "-") ++ "+"
    migrate <- getMigrate
    if migrate then
        doMigration
    else do
        cliState <- getCliState
        if cliState then do
            forkIO $ run port app
            repl
        else run port app

