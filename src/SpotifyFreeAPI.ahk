#Include, %A_LineFile%\..\lib\Edge\Edge.ahk
class SpotifyAPI{
    static js_find_declr:= "const req='function'==typeof webpackJsonp?webpackJsonp([],{__extra_id__:(e,n,t)=>n.default=t},['__extra_id__']).default:webpackJsonp.push([[],{__extra_id__:(e,n,t)=>e.exports=t},[['__extra_id__']]]);delete req.m.__extra_id__,delete req.c.__extra_id__;const find=(e,n={})=>{const{cacheOnly:t=!0}=n;for(let n in req.c)if(req.c.hasOwnProperty(n)){let t=req.c[n].exports;if(t&&t.__esModule&&t.default&&e(t.default))return t.default;if(t&&e(t))return t}if(t)return console.warn('Cannot find loaded module in cache'),null;console.warn('Cannot find loaded module in cache. Loading all modules may have unexpected side effects');for(let n=0;n<req.m.length;++n)try{let t=req(n);if(t&&t.__esModule&&t.default&&e(t.default))return t.default;if(t&&e(t))return t}catch(e){}return console.warn('Cannot find module'),null},findByUniqueProperties=(e,n)=>find(n=>e.every(e=>void 0!==n[e]),n);"
    , js_getUserId:= "findByUniqueProperties(['getActiveSocketAndDevice']).getActiveSocketAndDevice()?.socket.accountId;"
    , js_getToken:= "findByUniqueProperties(['SpotifyAPI']).getAccessToken('{}');"
    
    __New(SpotifyUserName:=""){
        this.EdgeProfile:= "spotfyEdgeProfile"
        this.spotifyUserName:= SpotifyUserName
        FileCreateDir, % this.EdgeProfile
        authCheck:
        if(!this.isDiscordAuthed()){
            this.discordLogin()
            Goto, authCheck
        }
        this.edgeInst := new Edge(A_ScriptDir "\" this.EdgeProfile,,"--headless --disable-gpu https://discord.com/app")
        this.pageInst := this.edgeInst.GetPageByURL("https://discord.com")
        Sleep, 3000
        this.updateToken()
        this.ws:= new SpotifyWebSocket(this.token)
        OnExit(ObjBindMethod(this,"onExit"))
        funcObj:= objBindMethod(this,"updateToken")
        SetTimer, % funcObj, 60000
    }

    CallAPI(method, endPoint, body:=""){
        url:= "https://api.spotify.com/v1/" . endpoint
        http := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		http.Open(method, url, false)
        http.SetRequestHeader("Authorization", "Bearer " . this.token)
        http.Send(body)
        Try reponse:= Edge.JSON.load(http.ResponseText)
        if(http.Status == 401){
            this.updateToken()
            return this.CallAPI(method, endPoint, body)
        }else if(http.Status > 299){ ;error
            throw, Exception(Format("(Status code: {1:}) {2:}: {3:}", http.Status, reponse.Error.Reason, reponse.Error.Message))
        }
        return reponse
    }

    ResumePlayback(){
        return this.CallAPI("PUT", "me/player/play")
    }

    PausePlayback(){
        return this.CallAPI("PUT", "me/player/pause")
    }

    TogglePlayback() {
		return ((this.GetCurrentPlaybackInfo()["is_playing"] = 0) ? (this.ResumePlayback()) : (this.PausePlayback()))
	}

    SetVolume(volume, IncDec:=0){
        if(IncDec)
            volume:= this.GetVolume() + volume
        volume:= Min(Max(volume, 0), 100) ;to make sure it stays between 0 and 100
        return this.CallAPI("PUT", "me/player/volume?volume_percent=" . volume)
    }

    GetVolume(){
        return this.GetCurrentPlaybackInfo().device.volume_percent
    }

    GetCurrentPlaybackInfo(){
        return this.CallAPI("GET", "me/player")
    }

    NextTrack(){
        return this.CallAPI("POST", "me/player/next")
    }

    PreviousTrack(){
        return this.CallAPI("POST", "me/player/previous")
    }

    isDiscordAuthed(){
        edg := new Edge(A_ScriptDir "\" this.EdgeProfile,,"--headless --disable-gpu https://discord.com/app")
        page := edg.GetPageByURL("https://discord.com")
        page.WaitForLoad()
        sleep 1000
        url:= page.Evaluate("window.location.pathname").value
        page.Call("Browser.close")
        page.Disconnect()
        edg.Kill()
        return InStr(url, "login")? 0 : 1
    }

    discordLogin(){
        MsgBox, 65, SpotifyNonPremiumAPI, You need to sign in to your discord account
        IfMsgBox, Cancel
            return 0
        Try{
            MsgBox, 64, SpotifyNonPremiumAPI, Make sure to close the browser window after signing in
            edg := new Edge(A_ScriptDir "\" this.EdgeProfile,,"--app=https://discord.com/login")
            page := edg.GetPageByURL("https://discord.com")
            page.WaitForLoad()
            sleep 2000
            while(InStr(page.Evaluate("window.location.pathname").value, "login")){
            }
            page.WaitForLoad()
            sleep 500
            WinWaitClose, "Discord ahk_exe msedge.exe"
            page.Call("Browser.close")
            Try page.Disconnect()
            edg.Kill()
        }catch err {
            MsgBox,16, SpotifyNonPremiumAPI, % "An error occured: " . err.message
            return 0
        }
        MsgBox, 64, SpotifyNonPremiumAPI, Sign in successful
        return 1
    }

    updateToken(){
        Try this.pageInst.Evaluate("findByUniqueProperties")
        catch err { ;function not defined
            this.pageInst.Evaluate(this.js_find_declr)
        }
        if(!this.spotifyUserName)
            this.spotifyUserName:= this.getUserName()
        promise:= this.pageInst.Evaluate(Format(this.js_getToken, this.spotifyUserName)).objectId
        this.token:= this.pageInst.Await(promise).value.body.access_token
    }

    getUserName(){
        static retries:= 0
        userNameLbl:
        Try val:= this.pageInst.Evaluate(this.js_getUserId).value
        if(!val || val = "undefined"){
            if(retries++ < 3){
                Sleep, 1000
                Goto, userNameLbl
            }
            MsgBox, 49, SpotifyNonPremiumAPI, Could not fetch your Spotify username`nPlay anything on spotify then click OK
            IfMsgBox, Cancel
                Throw, "Could not fetch your Spotify username"
            sleep 1000
            Goto, userNameLbl
        }
        retries:= 0
        return val
    }

    onExit(){
        this.pageInst.Call("Browser.close")
        this.pageInst.Disconnect()
        this.edgeInst.Kill()
    }

    class SpotifyWebSocket{ ; https://github.com/G33kDude/WebSocket.ahk
        __New(token)
        {
            static wb
            WS_URL:= "wss://dealer.spotify.com/?access_token=" token
            ; Create an IE instance
            Gui, +hWndhOld
            Gui, New, +hWndhWnd
            this.hWnd := hWnd
            Gui, Add, ActiveX, vWB, Shell.Explorer
            Gui, %hOld%: Default
            
            ; Write an appropriate document
            WB.Navigate("about:<!DOCTYPE html><meta http-equiv='X-UA-Compatible'"
            . "content='IE=edge'><body></body>")
            while (WB.ReadyState < 4)
                sleep, 50
            this.document := WB.document
            
            ; Add our handlers to the JavaScript namespace
            this.document.parentWindow.ahk_savews := this._SaveWS.Bind(this)
            this.document.parentWindow.ahk_event := this._Event.Bind(this)
            this.document.parentWindow.ahk_ws_url := WS_URL
            
            ; Add some JavaScript to the page to open a socket
            Script := this.document.createElement("script")
            Script.text := "ws = new WebSocket(ahk_ws_url);`n"
            . "ws.onopen = function(event){ ahk_event('Open', event); };`n"
            . "ws.onclose = function(event){ ahk_event('Close', event); };`n"
            . "ws.onerror = function(event){ ahk_event('Error', event); };`n"
            . "ws.onmessage = function(event){ ahk_event('Message', event); };"
            this.document.body.appendChild(Script)
        }
        
        ; Called by the JS in response to WS events
        _Event(EventName, Event)
        {
            this["On" EventName](Event)
        }
        
        ; Sends data through the WebSocket
        Send(Data)
        {
            this.document.parentWindow.ws.send(Data)
        }
        
        ; Closes the WebSocket connection
        Close(Code:=1000, Reason:="")
        {
            this.document.parentWindow.ws.close(Code, Reason)
        }
        
        ; Closes and deletes the WebSocket, removing
        ; references so the class can be garbage collected
        Disconnect()
        {
            if this.hWnd
            {
                this.Close()
                Gui, % this.hWnd ": Destroy"
                this.hWnd := False
            }
        }
    }
}

