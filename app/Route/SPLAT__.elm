module Route.SPLAT__ exposing (Data, Model, Msg, route)

-- import Page exposing (Page, PageWithState, StaticPayload)

import DataSource exposing (DataSource)
import DataSource.ElmRadio
import DataSource.ElmWeeklyRSS
import DataSource.File
import DataSource.Glob as Glob
import DataSource.Markdown
import DataSource.Notion as Notion
import Dict
import Effect
import Element exposing (..)
import Head
import Head.Seo as Seo
import Html
import Json.Decode as Decode
import Json.Decode.Pipeline exposing (hardcoded, optional, required)
import List.NonEmpty
import Pages.PageUrl exposing (PageUrl)
import Pages.Url
import Path
import Route
import RouteBuilder exposing (StatefulRoute, StaticPayload)
import Shared
import Theme
import Theme.Markdown
import Theme.Videos
import Timestamps exposing (Timestamps)
import Types_ exposing (..)
import View exposing (..)


type alias Model =
    ()


type alias Msg =
    Types_.Msg


type alias RouteParams =
    { splat : List String }


type alias Data =
    -- { ui : Types_.Model -> Types_.GlobalData -> List (Element Types_.Msg)
    { meta : DataSource.Markdown.Meta
    , timestamps : Timestamps
    , global : Types_.GlobalData
    , rawMarkdown : String
    , path : String
    }


route : StatefulRoute RouteParams Data () Types_.Msg
route =
    RouteBuilder.preRender
        { head = head
        , pages = routes
        , data = data
        }
        |> RouteBuilder.buildWithSharedState
            { view =
                \pageUrlMaybe modelShared templateModel static ->
                    view pageUrlMaybe modelShared static
            , init =
                \pageUrlMaybe modelShared static ->
                    ( (), Cmd.none )
            , update =
                -- , update : PageUrl -> StaticPayload data routeParams -> msg -> model -> Shared.Model -> ( model, Effect msg, Maybe Shared.Msg )
                \pageUrl staticPayload templateMsg templateModel modelShared ->
                    -- SPLAT__ uses Types_.Msg same as shared, so just route all handling up to shared.
                    -- @TODO fix this after type checking....
                    -- ( (), Effect.none, Just templateMsg )
                    ( (), Effect.none, Just Types_.Noop )
            , subscriptions =
                \pageUrlMaybe routeParams path templateModel modelShared ->
                    Sub.none
            }


routes : DataSource (List RouteParams)
routes =
    content
        |> DataSource.map
            (List.map
                (\contentPage ->
                    { splat = contentPage }
                )
            )


content : DataSource (List (List String))
content =
    Glob.succeed
        (\leadingPath last ->
            if last == "index" then
                leadingPath

            else
                leadingPath ++ [ last ]
        )
        |> Glob.match (Glob.literal "content/")
        |> Glob.capture Glob.recursiveWildcard
        |> Glob.match (Glob.literal "/")
        |> Glob.capture Glob.wildcard
        |> Glob.match (Glob.literal ".md")
        |> Glob.toDataSource


data : RouteParams -> DataSource Data
data routeParams =
    DataSource.Markdown.routeAsLoadedPageAndThen routeParams
        (\path d ->
            let
                getVideos =
                    if d.rawMarkdown |> String.contains "<video" then
                        Notion.recursiveGetVideos Nothing

                    else if path == "content/index.md" then
                        Notion.getVideos 3

                    else
                        DataSource.succeed []

                onlyOn p datasource default =
                    if path == p then
                        datasource

                    else
                        DataSource.succeed default
            in
            DataSource.map5
                (\ts videos videosCount podcastM newsletterM ->
                    let
                        data_ : Data
                        data_ =
                            { meta = d.meta
                            , timestamps = ts
                            , rawMarkdown = d.rawMarkdown
                            , path = d.path
                            , global =
                                { videos = videos
                                , videosCount = videosCount
                                , latestPodcast = podcastM
                                , latestNewsletter = newsletterM
                                }
                            }
                    in
                    data_
                )
                (Timestamps.data path)
                getVideos
                (onlyOn "content/index.md" Notion.getVideosCount 0)
                (onlyOn "content/index.md" (DataSource.ElmRadio.episodeLatest |> DataSource.map Just) Nothing)
                (onlyOn "content/index.md" (DataSource.ElmWeeklyRSS.newsletterLatest |> DataSource.map Just) Nothing)
        )


head : StaticPayload Data RouteParams -> List Head.Tag
head static =
    Seo.summary
        { canonicalUrlOverride = Nothing
        , siteName = "Elmcraft"
        , image =
            { url = Path.fromString "/images/elmcraft-logo.png" |> Pages.Url.fromPath
            , alt = "Elmcraft logo"
            , dimensions = Nothing
            , mimeType = Nothing
            }
        , description = static.data.meta.description
        , locale = Nothing
        , title = static.data.meta.title
        }
        |> Seo.website


view :
    Maybe PageUrl
    -> Shared.Model
    -> StaticPayload Data RouteParams
    -> View Types_.Msg
view maybeUrl sharedModel static =
    { title = static.data.meta.title
    , content = DataSource.Markdown.markdownRendererDirect static.data.rawMarkdown static.data.path sharedModel static.data.global
    , route = static.data.meta.route
    , timestamps = static.data.timestamps
    , status = static.data.meta.status
    , published = static.data.meta.published
    }