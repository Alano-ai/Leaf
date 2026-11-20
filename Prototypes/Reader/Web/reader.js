// SPDX-License-Identifier: GPL-3.0-only

import { EPUB } from './foliate/epub.js'
import { isMOBI, MOBI } from './foliate/mobi.js'
import { unzlibSync } from './foliate/vendor/fflate.js'
import { configure, ZipReader, BlobReader, BlobWriter, TextWriter } from './foliate/vendor/zip.js'
import './foliate/view.js'

configure({ useWebWorkers: false })

async function openEPUB(data) {
    const entries = await new ZipReader(new BlobReader(data)).getEntries()
    if (entries.some(entry => entry.encrypted || entry.filename === 'META-INF/encryption.xml'))
        throw new Error('Protected EPUB is unsupported by this prototype')
    const size = entries.reduce((total, entry) => total + entry.uncompressedSize, 0)
    if (entries.length > 10000 || size > 512 * 1024 * 1024)
        throw new Error('EPUB exceeds the prototype’s archive limits')

    const byName = new Map(entries.map(entry => [entry.filename, entry]))
    if (!byName.has('META-INF/container.xml') || byName.size !== entries.length)
        throw new Error('Invalid EPUB archive')
    const loadText = name => byName.get(name)?.getData(new TextWriter(), { checkSignature: true }) ?? null
    const loadBlob = (name, type) => byName.get(name)?.getData(new BlobWriter(type), { checkSignature: true }) ?? null
    const getSize = name => byName.get(name)?.uncompressedSize ?? 0
    return new EPUB({ loadText, loadBlob, getSize }).init()
}

const view = document.createElement('foliate-view')
const documentSections = new WeakMap()
document.body.append(view)
view.addEventListener('external-link', event => event.preventDefault())
view.addEventListener('load', ({ detail }) => documentSections.set(detail.doc, detail.index))

const afterLayout = () => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve)))

function chapters(entries) {
    return (entries ?? []).flatMap(item => [
        ...(item.href ? [{ label: item.label, href: item.href }] : []),
        ...chapters(item.subitems),
    ])
}

async function state(targetIndex) {
    await afterLayout()
    const documents = view.renderer.getContents().map(content => content.doc).filter(Boolean)
    const location = view.lastLocation
    return {
        cfi: location?.cfi ?? '',
        chapter: location?.tocItem?.label ?? '',
        fraction: location?.fraction ?? 0,
        textVisible: documents.some(doc => doc.body?.textContent.trim().length > 0),
        images: documents.reduce((count, doc) =>
            count + [...doc.images].filter(image => image.naturalWidth > 0).length, 0),
        fonts: documents.reduce((count, doc) =>
            count + [...doc.fonts].filter(font => font.status === 'loaded').length, 0),
        scriptPresent: documents.some(doc => doc.querySelector('#book-script-probe')),
        scriptRan: documents.some(doc => doc.documentElement.dataset.bookScriptRan === 'yes'),
        remoteImageLoaded: documents.some(doc => doc.querySelector('#offline-probe')?.naturalWidth > 0),
        localFileLoaded: documents.some(doc => doc.querySelector('#local-file-probe')?.naturalWidth > 0),
        targetVisible: targetIndex === undefined ? undefined :
            documents.some(doc => documentSections.get(doc) === targetIndex),
    }
}

window.reader = {
    async open(format) {
        const response = await fetch('/book')
        if (!response.ok) throw new Error('Unable to read the local file')
        const bytes = await response.blob()
        let book
        let kindleVersion
        if (format === 'epub') book = await openEPUB(bytes)
        else {
            if (!await isMOBI(bytes)) throw new Error('Invalid MOBI/KF8 file')
            const mobi = new MOBI({ unzlib: unzlibSync })
            book = await mobi.open(bytes)
            kindleVersion = mobi.headers.mobi.version
        }
        if (!book.sections.length) throw new Error('The book contains no readable pages')
        // Audio and video are outside the prototype. The renderer still loads local images and fonts.
        for (const section of book.sections) delete section.mediaOverlay
        await view.open(book)
        await view.init({ showTextStart: true })
        if (!view.lastLocation) await view.goTo(0)
        const contents = view.renderer.getContents()
        await Promise.all(contents.map(({ doc }) => doc?.fonts.ready))
        const result = await state()
        if (!result.cfi || !result.textVisible) throw new Error('No readable first page was rendered')
        return { ...result, chapters: chapters(book.toc), fixedLayout: view.isFixedLayout, kindleVersion }
    },
    async next() {
        await view.next()
        return state()
    },
    async previous() {
        await view.prev()
        return state()
    },
    async jump(href) {
        const target = view.isFixedLayout ? await view.resolveNavigation(href) : undefined
        await view.goTo(href)
        return state(target?.index)
    },
}
