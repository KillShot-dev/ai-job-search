using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Storage;
using Windows.Storage.FileProperties;

namespace FileRadar.Services;

public static class ThumbnailService
{
    public static async Task<BitmapImage?> TryLoadAsync(string path, uint size = 256)
    {
        try
        {
            if (!File.Exists(path)) return null;
            var file = await StorageFile.GetFileFromPathAsync(path);
            using var thumb = await file.GetThumbnailAsync(ThumbnailMode.SingleItem, size, ThumbnailOptions.ResizeThumbnail);
            if (thumb is null) return null;
            var bmp = new BitmapImage();
            await bmp.SetSourceAsync(thumb);
            return bmp;
        }
        catch
        {
            try
            {
                // Fallback for plain image paths when Storage thumbnail fails
                var ext = Path.GetExtension(path).ToLowerInvariant();
                if (ext is not (".png" or ".jpg" or ".jpeg" or ".gif" or ".bmp" or ".webp"))
                    return null;
                var bmp = new BitmapImage();
                bmp.DecodePixelWidth = (int)size;
                bmp.UriSource = new Uri(path);
                return bmp;
            }
            catch
            {
                return null;
            }
        }
    }
}
