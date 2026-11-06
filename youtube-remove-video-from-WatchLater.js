function sleep(ms) {
	s = ms*1000;
    return new Promise(resolve => setTimeout(resolve, s));
}

var i = 0; // start from
var videoCount = 500; // total number of videos

while (i<videoCount) {
document.querySelector("ytd-playlist-video-renderer:nth-child(3)>div:nth-child(3)>ytd-menu-renderer>yt-icon-button").click();
await sleep(1);	
document.querySelector("#items > ytd-menu-service-item-renderer:nth-child(3) > tp-yt-paper-item").click();
await sleep(1);
i++;
console.log(i);
}

